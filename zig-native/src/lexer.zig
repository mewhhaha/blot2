const std = @import("std");
const token = @import("token.zig");
pub const Tag = token.Tag;
pub const Token = token.Token;
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || error{SourceLimit};

pub const Code = enum {
    invalid_utf8,
    lexical_error,
    string_literal,
    string_escape,
    reserved_layout,
    reserved_selector_marker,
    reserved_import_marker,
    reserved_clause_marker,
    layout_tab,
    layout_indent,
    layout_suite,
    layout_dedent,
    integer_range,
    float_range,
    float_literal,
};

pub const Diagnostic = struct {
    code: Code,
    start: u32,
    end: u32,

    pub fn message(self: Diagnostic) []const u8 {
        return switch (self.code) {
            .invalid_utf8 => "Source is not valid UTF-8",
            .lexical_error => "No token matches this source character",
            .string_literal => "Expected a closing quote before the line ends",
            .string_escape => "String escapes are limited to quote, backslash, n, r and t",
            .reserved_layout => "Private layout markers cannot appear in source",
            .reserved_selector_marker => "Use '.' for a field selector",
            .reserved_import_marker => "Use 'from' in an import declaration",
            .reserved_clause_marker => "The spelling 'wherE' is reserved before a clause body",
            .layout_tab => "Use spaces for indentation",
            .layout_indent => "Top-level declarations must start at column 1",
            .layout_suite => "Expected an indented suite",
            .layout_dedent => "Dedent must match an enclosing indentation level",
            .integer_range => "Integer literal exceeds U32 (4294967295)",
            .float_range => "Floating-point literal exceeds finite F32 range",
            .float_literal => "Invalid F32 literal",
        };
    }
};

pub const Result = struct {
    tokens: std.ArrayList(Token) = .empty,
    comments: std.ArrayList(Token) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub fn deinit(self: *Result, allocator: Allocator) void {
        self.tokens.deinit(allocator);
        self.comments.deinit(allocator);
        self.diagnostics.deinit(allocator);
        self.* = .{};
    }
};

fn emit(list: *std.ArrayList(Token), allocator: Allocator, tag: Tag, start: usize, end: usize) Allocator.Error!void {
    try list.append(allocator, .{ .tag = tag, .start = @intCast(start), .end = @intCast(end) });
}

fn diagnose(result: *Result, allocator: Allocator, code: Code, start: usize, end: usize) Allocator.Error!void {
    try result.diagnostics.append(allocator, .{ .code = code, .start = @intCast(start), .end = @intCast(end) });
}

fn lower(c: u8) bool {
    return c >= 'a' and c <= 'z';
}
fn upper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}
fn digit(c: u8) bool {
    return c >= '0' and c <= '9';
}
fn ident(c: u8) bool {
    return lower(c) or digit(c) or c == '_';
}
fn typeIdent(c: u8) bool {
    return ident(c) or upper(c);
}
fn hex(c: u8) bool {
    return digit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}
fn symbolic(c: u8) bool {
    return std.mem.indexOfScalar(u8, "+*$%=!<>^&|?-", c) != null;
}

const Number = struct { end: usize, tag: Tag };
fn digits(source: []const u8, start: usize, hexadecimal: bool) usize {
    var at = start;
    while (at < source.len) {
        if (if (hexadecimal) hex(source[at]) else digit(source[at])) at += 1 else if (source[at] == '_' and at + 1 < source.len and
            (if (hexadecimal) hex(source[at + 1]) else digit(source[at + 1]))) at += 2 else break;
    }
    return at;
}

/// Maximal matching follows the grammar, including its partial matches for
/// malformed numbers. For example 1e+ is INTEGER, IDENT, SYMBOL, not a FLOAT.
fn scanNumber(source: []const u8, start: usize) Number {
    if (source[start] == '0' and start + 2 < source.len and
        (source[start + 1] == 'x' or source[start + 1] == 'X') and hex(source[start + 2]))
        return .{ .end = digits(source, start + 2, true), .tag = .integer };
    var at = digits(source, start, false);
    var tag: Tag = .integer;
    if (at + 1 < source.len and source[at] == '.' and digit(source[at + 1])) {
        at = digits(source, at + 1, false);
        tag = .float;
    }
    if (at < source.len and (source[at] == 'e' or source[at] == 'E')) {
        var exponent = at + 1;
        if (exponent < source.len and (source[exponent] == '+' or source[exponent] == '-')) exponent += 1;
        if (exponent < source.len and digit(source[exponent])) {
            at = digits(source, exponent, false);
            tag = .float;
        }
    }
    return .{ .end = at, .tag = tag };
}

pub fn integerValue(text: []const u8) error{ InvalidInteger, IntegerRange }!u32 {
    const radix: u32 = if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) 16 else 10;
    var at: usize = if (radix == 16) 2 else 0;
    const first = at;
    if (at == text.len) return error.InvalidInteger;
    var value: u32 = 0;
    while (at < text.len) : (at += 1) {
        const c = text[at];
        if (c == '_') {
            if (at == first or at + 1 == text.len or text[at - 1] == '_' or
                !(if (radix == 16) hex(text[at + 1]) else digit(text[at + 1]))) return error.InvalidInteger;
            continue;
        }
        if (!(if (radix == 16) hex(c) else digit(c))) return error.InvalidInteger;
        const n: u32 = if (digit(c)) c - '0' else if (upper(c)) c - 'A' + 10 else c - 'a' + 10;
        value = std.math.mul(u32, value, radix) catch return error.IntegerRange;
        value = std.math.add(u32, value, n) catch return error.IntegerRange;
    }
    return value;
}

pub fn floatBits(allocator: Allocator, text: []const u8) (Allocator.Error || error{ InvalidFloat, FloatRange })!u32 {
    if (text.len == 0 or !digit(text[0])) return error.InvalidFloat;
    const scanned = scanNumber(text, 0);
    if (scanned.tag != .float or scanned.end != text.len) return error.InvalidFloat;
    var cleaned: std.ArrayList(u8) = .empty;
    defer cleaned.deinit(allocator);
    const input = if (std.mem.indexOfScalar(u8, text, '_') != null) blk: {
        try cleaned.ensureTotalCapacity(allocator, text.len);
        for (text) |c| if (c != '_') {
            cleaned.appendAssumeCapacity(c);
        };
        break :blk cleaned.items;
    } else text;
    // Parsing directly to binary32 avoids decimal -> binary64 -> binary32
    // double rounding, including exact halfway cases and subnormals.
    const value = std.fmt.parseFloat(f32, input) catch return error.InvalidFloat;
    if (!std.math.isFinite(value)) return error.FloatRange;
    return @bitCast(value);
}

fn validateSource(allocator: Allocator, source: []const u8, result: *Result) Allocator.Error!void {
    var at: usize = 0;
    while (at < source.len) {
        const width = std.unicode.utf8ByteSequenceLength(source[at]) catch {
            try diagnose(result, allocator, .invalid_utf8, at, at + 1);
            return;
        };
        if (width > source.len - at) {
            try diagnose(result, allocator, .invalid_utf8, at, source.len);
            return;
        }
        const point = std.unicode.utf8Decode(source[at..][0..width]) catch {
            try diagnose(result, allocator, .invalid_utf8, at, at + width);
            return;
        };
        if (point >= 0xe000 and point <= 0xe002) {
            try diagnose(result, allocator, .reserved_layout, at, at + width);
            return;
        }
        at += width;
    }
}

fn scan(allocator: Allocator, source: []const u8, result: *Result) Allocator.Error!void {
    var at: usize = 0;
    while (at < source.len) {
        const start = at;
        const c = source[at];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            at += 1;
            continue;
        }
        if (c == '/' and at + 1 < source.len and source[at + 1] == '/') {
            at += 2;
            while (at < source.len and source[at] != '\r' and source[at] != '\n') at += 1;
            try emit(&result.comments, allocator, .comment, start, at);
            continue;
        }
        if (c == '"') {
            at += 1;
            var terminated = false;
            while (at < source.len and source[at] != '\r' and source[at] != '\n') {
                if (source[at] == '"') {
                    at += 1;
                    terminated = true;
                    break;
                }
                if (source[at] == '\\') {
                    if (at + 1 == source.len or source[at + 1] == '\r' or source[at + 1] == '\n') break;
                    if (std.mem.indexOfScalar(u8, "\"\\nrt", source[at + 1]) == null)
                        try diagnose(result, allocator, .string_escape, at, at + 2);
                    at += 2;
                } else at += 1;
            }
            if (!terminated) try diagnose(result, allocator, .string_literal, start, at);
            try emit(&result.tokens, allocator, .string, start, at);
            continue;
        }
        if (digit(c)) {
            const number = scanNumber(source, at);
            at = number.end;
            // Numeric value bounds belong to source lowering; the grammar
            // recognizes the complete token independently of its U32/F32 value.
            try emit(&result.tokens, allocator, number.tag, start, at);
            continue;
        }
        if (std.mem.startsWith(u8, source[at..], "froM") or std.mem.startsWith(u8, source[at..], "wherE")) {
            const from = source[at] == 'f';
            at += if (from) @as(usize, 4) else 5;
            try emit(&result.tokens, allocator, if (from) .private_from else .private_where, start, at);
            continue;
        }
        if (lower(c) or upper(c) or c == '_') {
            const capital = upper(c);
            at += 1;
            while (at < source.len and (if (capital) typeIdent(source[at]) else ident(source[at]))) at += 1;
            const kind = token.keyword(source[start..at]);
            try emit(&result.tokens, allocator, if (capital and kind == .identifier) .type_identifier else kind, start, at);
            continue;
        }
        if (c == '@' and at + 1 < source.len and (lower(source[at + 1]) or source[at + 1] == '_')) {
            at += 2;
            while (at < source.len and ident(source[at])) at += 1;
            while (at + 1 < source.len and source[at] == '.' and (lower(source[at + 1]) or source[at + 1] == '_')) {
                at += 2;
                while (at < source.len and ident(source[at])) at += 1;
            }
            try emit(&result.tokens, allocator, .intrinsic, start, at);
            continue;
        }
        if (symbolic(c) or c == '/') {
            at += 1;
            if (c != '/') while (at < source.len and symbolic(source[at])) {
                at += 1;
            };
            const spelling = source[start..at];
            const kind: Tag = if (std.mem.eql(u8, spelling, "->")) .arrow else if (std.mem.eql(u8, spelling, "=>")) .fat_arrow else if (std.mem.eql(u8, spelling, "<-")) .left_arrow else if (spelling.len != 1) .symbol else switch (c) {
                '$' => .dollar,
                '*' => .star,
                '^' => .caret,
                '|' => .pipe,
                '!' => .bang,
                '=' => .equal,
                else => .symbol,
            };
            try emit(&result.tokens, allocator, kind, start, at);
            continue;
        }
        at += 1;
        const kind: ?Tag = switch (c) {
            '(' => .l_paren,
            ')' => .r_paren,
            '[' => .l_bracket,
            ']' => .r_bracket,
            '{' => .l_brace,
            '}' => .r_brace,
            ',' => .comma,
            '#' => .hash,
            '@' => .at,
            '`' => .backtick,
            '~' => .tilde,
            ':' => if (at < source.len and source[at] == '=') blk: {
                at += 1;
                break :blk .colon_equal;
            } else .colon,
            '.' => if (at < source.len and source[at] == '.') blk: {
                at += 1;
                if (at < source.len and source[at] == '.') {
                    at += 1;
                    break :blk .ellipsis;
                }
                break :blk .dot_dot;
            } else .dot,
            else => null,
        };
        if (kind) |tag| try emit(&result.tokens, allocator, tag, start, at) else {
            // Source was validated, so consume one complete scalar on errors.
            at = start + (std.unicode.utf8ByteSequenceLength(c) catch unreachable);
            const code: Code = if (std.mem.eql(u8, source[start..at], "·")) .reserved_selector_marker else .lexical_error;
            try diagnose(result, allocator, code, start, at);
        }
    }
}

const Frame = struct { indent: usize, depth: i32 };
const Indentation = struct { width: usize, start: usize, tab: bool };

fn indentation(source: []const u8, starts: []const u32, at: u32) Indentation {
    var low: usize = 0;
    var high = starts.len;
    while (low + 1 < high) {
        const middle = low + (high - low) / 2;
        if (starts[middle] <= at) low = middle else high = middle;
    }
    const start = starts[low];
    var end: usize = start;
    var tab = false;
    while (end < at and (source[end] == ' ' or source[end] == '\t')) : (end += 1) tab = tab or source[end] == '\t';
    return .{ .width = end - start, .start = start, .tab = tab };
}

fn brokenLine(source: []const u8, previous: Token, next: Token) bool {
    for (source[previous.end..next.start]) |c| if (c == '\r' or c == '\n') return true;
    return false;
}

fn close(tag: Tag) bool {
    return tag == .r_paren or tag == .r_bracket or tag == .r_brace;
}
fn open(tag: Tag) bool {
    return tag == .l_paren or tag == .l_bracket or tag == .l_brace;
}

fn layout(allocator: Allocator, source: []const u8, result: *Result) Allocator.Error!void {
    var raw = result.tokens;
    result.tokens = .empty;
    defer raw.deinit(allocator);
    var starts: std.ArrayList(u32) = .empty;
    defer starts.deinit(allocator);
    try starts.append(allocator, 0);
    for (source, 0..) |c, index| if (c == '\r' or c == '\n') {
        try starts.append(allocator, @intCast(index + 1));
    };
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(allocator);
    try frames.append(allocator, .{ .indent = 0, .depth = 0 });
    var depth: i32 = 0;
    var operations_depth: i32 = -1;
    if (raw.items.len != 0) {
        const first = raw.items[0];
        const width = indentation(source, starts.items, first.start);
        if (width.tab) {
            try diagnose(result, allocator, .layout_tab, width.start, first.start);
            return;
        }
        if (width.width != 0) {
            try diagnose(result, allocator, .layout_indent, first.start, first.start);
            return;
        }
    }
    for (raw.items, 0..) |current, index| {
        const previous: ?Token = if (index != 0) raw.items[index - 1] else null;
        const broken = if (previous) |prev| brokenLine(source, prev, current) else false;
        if (close(current.tag) and frames.items.len > 1 and frames.items[frames.items.len - 1].depth == depth) {
            try emit(&result.tokens, allocator, .newline, current.start, current.start);
            while (frames.items.len > 1 and frames.items[frames.items.len - 1].depth == depth) {
                _ = frames.pop();
                try emit(&result.tokens, allocator, .dedent, current.start, current.start);
                if (frames.items.len > 1 and frames.items[frames.items.len - 1].depth == depth)
                    try emit(&result.tokens, allocator, .newline, current.start, current.start);
            }
        } else if (broken and depth == operations_depth) {
            if (previous.?.tag != .colon and previous.?.tag != .arrow)
                try emit(&result.tokens, allocator, .newline, current.start, current.start);
        } else if (broken) {
            const frame = frames.items[frames.items.len - 1];
            var request_clause = false;
            if (previous.?.tag == .fat_arrow) {
                var first = index - 1;
                while (first > 0 and !brokenLine(source, raw.items[first - 1], raw.items[first])) first -= 1;
                request_clause = raw.items[first].tag == .kw_effect or raw.items[first].tag == .kw_complete;
                for (raw.items[first .. index - 1]) |part| {
                    if (part.tag == .equal or part.tag == .kw_fn or part.tag == .fat_arrow) request_clause = false;
                }
            }
            const suite = previous.?.tag == .colon or previous.?.tag == .kw_of or request_clause;
            if (suite or depth == frame.depth) {
                const width = indentation(source, starts.items, current.start);
                if (width.tab) {
                    try diagnose(result, allocator, .layout_tab, width.start, current.start);
                    return;
                }
                if (suite) {
                    if (width.width <= indentation(source, starts.items, previous.?.start).width) {
                        try diagnose(result, allocator, .layout_suite, current.start, current.start);
                        return;
                    }
                    try emit(&result.tokens, allocator, .newline, current.start, current.start);
                    try emit(&result.tokens, allocator, .indent, current.start, current.start);
                    try frames.append(allocator, .{ .indent = width.width, .depth = depth });
                } else if (width.width > frame.indent or (width.width == frame.indent and current.tag == .pipe)) {
                    // Continuations and aligned pattern alternatives do not open suites.
                } else {
                    try emit(&result.tokens, allocator, .newline, current.start, current.start);
                    while (width.width < frames.items[frames.items.len - 1].indent) {
                        _ = frames.pop();
                        try emit(&result.tokens, allocator, .dedent, current.start, current.start);
                        try emit(&result.tokens, allocator, .newline, current.start, current.start);
                    }
                    if (width.width != frames.items[frames.items.len - 1].indent) {
                        try diagnose(result, allocator, .layout_dedent, current.start, current.start);
                        return;
                    }
                }
            }
        }
        if (current.tag == .l_brace and index >= 3 and raw.items[index - 1].tag == .equal and
            raw.items[index - 2].tag == .kw_effect and raw.items[index - 3].tag == .kw_is) operations_depth = depth + 1;
        if (open(current.tag)) depth += 1;
        if (close(current.tag)) depth -= 1;
        if (depth < operations_depth) operations_depth = -1;
        try result.tokens.append(allocator, current);
    }
    if (raw.items.len != 0) {
        try emit(&result.tokens, allocator, .newline, source.len, source.len);
        while (frames.items.len > 1) {
            _ = frames.pop();
            try emit(&result.tokens, allocator, .dedent, source.len, source.len);
            try emit(&result.tokens, allocator, .newline, source.len, source.len);
        }
    }
}

fn annotationColon(tokens: []const Token, index: usize) bool {
    var nested: usize = 0;
    var cursor = index;
    while (cursor != 0) {
        cursor -= 1;
        const tag = tokens[cursor].tag;
        if (close(tag)) {
            nested += 1;
            continue;
        }
        if (open(tag)) {
            if (nested != 0) {
                nested -= 1;
                continue;
            }
            if (tag != .l_paren) return false;
        }
        if (nested != 0) continue;
        switch (tag) {
            .kw_let, .kw_const, .kw_fn => return true,
            .newline, .equal, .fat_arrow, .left_arrow, .comma => return false,
            else => {},
        }
    }
    return false;
}

fn contextual(allocator: Allocator, source: []const u8, result: *Result) Allocator.Error!void {
    var importing = false;
    var braces: i32 = 0;
    var annotation: ?i32 = null;
    for (result.tokens.items, 0..) |*current, index| {
        const tag = current.tag;
        if (tag == .kw_import) importing = true;
        if (tag == .newline) importing = false;
        if (importing and index + 1 < result.tokens.items.len and result.tokens.items[index + 1].tag == .string) {
            if (tag == .private_from) try diagnose(result, allocator, .reserved_import_marker, current.start, current.end) else if (tag == .identifier and std.mem.eql(u8, current.text(source), "from")) current.tag = .kw_from;
        }
        if (tag == .l_brace) braces += 1 else if (tag == .r_brace) braces -= 1;
        if (annotation) |level| if (braces < level) {
            annotation = null;
        };
        if (tag == .colon and annotationColon(result.tokens.items, index)) annotation = braces else if (annotation == braces and (tag == .newline or tag == .equal or tag == .fat_arrow or tag == .left_arrow or tag == .colon_equal))
            annotation = null
        else if (annotation == braces and index + 1 < result.tokens.items.len and result.tokens.items[index + 1].tag == .l_brace) {
            if (tag == .private_where) try diagnose(result, allocator, .reserved_clause_marker, current.start, current.end) else if (tag == .identifier and std.mem.eql(u8, current.text(source), "where")) current.tag = .kw_where;
        }
        if (tag == .dot) {
            const adjacent = index != 0 and result.tokens.items[index - 1].end == current.start;
            const before = if (current.start != 0) source[current.start - 1] else 0;
            if (!adjacent or !(typeIdent(before) or before == ']' or before == ')' or before == '}')) current.tag = .selector;
        }
    }
}

pub fn lex(allocator: Allocator, source: []const u8) Error!Result {
    if (source.len > std.math.maxInt(u32)) return error.SourceLimit;
    var result: Result = .{};
    errdefer result.deinit(allocator);
    try validateSource(allocator, source, &result);
    if (result.diagnostics.items.len == 0) try scan(allocator, source, &result);
    if (result.diagnostics.items.len == 0) {
        try layout(allocator, source, &result);
        if (result.diagnostics.items.len == 0) try contextual(allocator, source, &result);
    }
    try emit(&result.tokens, allocator, .eof, source.len, source.len);
    return result;
}

fn expectTags(source: []const u8, expected: []const Tag) !void {
    var result = try lex(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    try std.testing.expectEqual(expected.len, result.tokens.items.len);
    for (expected, result.tokens.items) |tag, actual| try std.testing.expectEqual(tag, actual.tag);
}

test "flat tokens preserve longest matches and source byte spans" {
    try expectTags("const x = @u32.add 0xFF_FF 1.25e-2 // note\n", &.{
        .kw_const, .identifier, .equal, .intrinsic, .integer, .float, .newline, .eof,
    });
    try expectTags("1..4 1e+ 1__2 ++ /* */", &.{
        .integer, .dot_dot,    .integer, .integer, .identifier, .symbol,
        .integer, .identifier, .symbol,  .symbol,  .star,       .star,
        .symbol,  .newline,    .eof,
    });
    var result = try lex(std.testing.allocator, "//😀\nconst text = \"π\\n·\"\n");
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    try std.testing.expectEqualStrings("//😀", result.comments.items[0].text("//😀\nconst text = \"π\\n·\"\n"));
    try std.testing.expectEqual(@as(u32, 7), result.tokens.items[0].start);
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(Token));
}

test "nested do layout, continuations, delimiter closures and final comments" {
    const source = "const answer = fn () => do:\n  let value = do:\n    return (\n      @u32.add 20\n      22)\n  return value // trailing";
    var result = try lex(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    var indents: usize = 0;
    var dedents: usize = 0;
    var newlines: usize = 0;
    for (result.tokens.items) |current| {
        if (current.tag == .indent) indents += 1;
        if (current.tag == .dedent) dedents += 1;
        if (current.tag == .newline) newlines += 1;
        if (current.tag == .indent or current.tag == .dedent or current.tag == .newline)
            try std.testing.expectEqual(current.start, current.end);
    }
    try std.testing.expectEqual(@as(usize, 2), indents);
    try std.testing.expectEqual(indents, dedents);
    try std.testing.expectEqual(@as(usize, 6), newlines);
    try expectTags("const x = (do:\n  return 1)\n", &.{
        .kw_const, .identifier, .equal,     .l_paren, .kw_do,   .colon,
        .newline,  .indent,     .kw_return, .integer, .newline, .dedent,
        .r_paren,  .newline,    .eof,
    });
}

test "request clause suites and effect operation line boundaries" {
    const source = "const h = fn c => do:\n  for let r in c:\n    case r of\n      effect State.get unit =>\n        yield 1\n      complete value =>\n        return value\n";
    var result = try lex(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    var indents: usize = 0;
    for (result.tokens.items) |current| if (current.tag == .indent) {
        indents += 1;
    };
    try std.testing.expectEqual(@as(usize, 5), indents);
    try expectTags("type State a is effect = {\n  get: Unit -> a\n  set: a -> Unit\n}\n", &.{
        .kw_type,    .type_identifier, .identifier, .kw_is,           .kw_effect,       .equal,      .l_brace,
        .newline,    .identifier,      .colon,      .type_identifier, .arrow,           .identifier, .newline,
        .identifier, .colon,           .identifier, .arrow,           .type_identifier, .newline,    .r_brace,
        .newline,    .eof,
    });
}

test "contextual from, annotation where and leading selectors" {
    const source = "import { where } from \"./where\"\nconst from = fn x => x\nconst f: a -> a where {has \"member\" a} = fn x => x\nconst r = {where: from}\nconst s = .field\nconst v = r.field\n";
    var result = try lex(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    var froms: usize = 0;
    var wheres: usize = 0;
    var selectors: usize = 0;
    var dots: usize = 0;
    for (result.tokens.items) |current| switch (current.tag) {
        .kw_from => froms += 1,
        .kw_where => wheres += 1,
        .selector => selectors += 1,
        .dot => dots += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), froms);
    try std.testing.expectEqual(@as(usize, 1), wheres);
    try std.testing.expectEqual(@as(usize, 1), selectors);
    try std.testing.expectEqual(@as(usize, 1), dots);
}

fn expectDiagnostic(source: []const u8, code: Code) !void {
    var result = try lex(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.diagnostics.items.len != 0);
    try std.testing.expectEqual(code, result.diagnostics.items[0].code);
}

test "invalid layout, private markers, strings and Unicode report diagnostics" {
    try expectDiagnostic("const f = fn () => do:\n\treturn 1", .layout_tab);
    try expectDiagnostic("  const f = 1", .layout_indent);
    try expectDiagnostic("const f = fn () => do:\n  let a = 1\n return a", .layout_dedent);
    try expectDiagnostic("const f = fn () => do:\nreturn 1", .layout_suite);
    try expectDiagnostic("const f = fn () =>\n  do:\n  return 1", .layout_suite);
    try expectDiagnostic("// \u{e000}", .reserved_layout);
    try expectDiagnostic("const s = ·name", .reserved_selector_marker);
    try expectDiagnostic("import { a } froM \"a\"", .reserved_import_marker);
    try expectDiagnostic("const f: a wherE {} = 1", .reserved_clause_marker);
    try expectDiagnostic("const s = \"\\q\"", .string_escape);
    try expectDiagnostic("const s = \"missing\n", .string_literal);
    try expectDiagnostic("const s = \"\xff\"", .invalid_utf8);
    try expectDiagnostic("const s = \"\xed\xa0\x80\"", .invalid_utf8);
}

test "numeric validation preserves U32 and exact F32 rounding" {
    try std.testing.expectEqual(@as(u32, 0xffffffff), try integerValue("0xFFFF_FFFF"));
    try std.testing.expectEqual(@as(u32, 0xffffffff), try integerValue("4_294_967_295"));
    try std.testing.expectError(error.InvalidInteger, integerValue("0x_1"));
    try std.testing.expectError(error.InvalidInteger, integerValue("1__2"));
    // Range belongs to source value conversion. The grammar token stream
    // remains available so later syntax can reject before source lowering.
    for ([_][]const u8{ "const value = 4294967296", "const value = 0x1_0000_0000", "const value = 1e999" }) |source| {
        var tokens = try lex(std.testing.allocator, source);
        defer tokens.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    }
    try std.testing.expectError(error.IntegerRange, integerValue("4294967296"));
    try std.testing.expectError(error.IntegerRange, integerValue("0x1_0000_0000"));
    try std.testing.expectError(error.FloatRange, floatBits(std.testing.allocator, "1e999"));
    try std.testing.expectEqual(@as(u32, 0x3f800000), try floatBits(std.testing.allocator, "1.000000059604644775390625"));
    try std.testing.expectEqual(@as(u32, 0x3f800001), try floatBits(std.testing.allocator, "1.000000059604644775390626"));
    try std.testing.expectEqual(@as(u32, 1), try floatBits(std.testing.allocator, "1.401298464324817e-45"));
    try std.testing.expectEqual(@as(u32, 0), try floatBits(std.testing.allocator, "1e-999"));
    try std.testing.expectEqual(@as(u32, 0x3f800000), try floatBits(std.testing.allocator, "1_0.0e-1"));
}

fn allocationScenario(allocator: Allocator) !void {
    const source = "// π\nimport { value } from \"mod\"\nconst result: U32 = fn () => do:\n  let x = 1_0.0e-1\n  return value\n";
    var result = try lex(allocator, source);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    var invalid = try lex(allocator, "const f = fn () => do:\n return \"\\q\"");
    defer invalid.deinit(allocator);
    try std.testing.expect(invalid.diagnostics.items.len != 0);
}

test "all lexer allocation failures release tokens, trivia and scratch" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "mixed line endings preserve layout tags and original byte spans" {
    const lines = [_][]const u8{
        "// leading comment", "const before = 1", "const answer = fn () => do:",
        "  let value = do:",  "    return 41",    "  return @u32.add value 1",
        "",
    };
    var expected: std.ArrayList(Tag) = .empty;
    defer expected.deinit(std.testing.allocator);
    const endings = [_][]const u8{ "\n", "\r", "\r\n" };
    for (0..4) |variant| {
        var source: std.ArrayList(u8) = .empty;
        defer source.deinit(std.testing.allocator);
        for (lines, 0..) |line, index| {
            try source.appendSlice(std.testing.allocator, line);
            if (index + 1 < lines.len)
                try source.appendSlice(std.testing.allocator, endings[if (variant == 3) index % 3 else variant]);
        }
        var result = try lex(std.testing.allocator, source.items);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
        if (variant == 0) for (result.tokens.items) |current| {
            try expected.append(std.testing.allocator, current.tag);
        } else {
            try std.testing.expectEqual(expected.items.len, result.tokens.items.len);
            for (result.tokens.items, expected.items) |current, tag| try std.testing.expectEqual(tag, current.tag);
        };
        for (result.tokens.items) |current| {
            if (current.tag == .kw_return) try std.testing.expectEqualStrings("return", current.text(source.items));
        }
    }
}

/// This integration check is optional in source-only distributions. When the
/// repository/sibling project is available it lexes actual files, including
/// requests, annotated predicates, nested loops and the complete gdev sources.
fn corpusDirectory(path: []const u8) !usize {
    const io = std.testing.io;
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer dir.close(io);
    var walker = try dir.walk(std.testing.allocator);
    defer walker.deinit();
    var count: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".blot")) continue;
        const source = try dir.readFileAlloc(io, entry.path, std.testing.allocator, .limited(16 * 1024 * 1024));
        defer std.testing.allocator.free(source);
        var result = try lex(std.testing.allocator, source);
        defer result.deinit(std.testing.allocator);
        if (result.diagnostics.items.len != 0) {
            const diagnostic = result.diagnostics.items[0];
            std.debug.print("{s}/{s}:{d}: {s}: {s}\n", .{ path, entry.path, diagnostic.start, @tagName(diagnostic.code), diagnostic.message() });
        }
        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
        try std.testing.expectEqual(Tag.eof, result.tokens.items[result.tokens.items.len - 1].tag);
        for (result.tokens.items) |current| {
            try std.testing.expect(current.start <= current.end and current.end <= source.len);
        }
        count += 1;
    }
    return count;
}

test "real examples, standard library and available gdev files lex cleanly" {
    var count = try corpusDirectory("examples");
    if (count == 0) count = try corpusDirectory("../examples");
    if (count == 0) return error.SkipZigTest;
    try std.testing.expect(count >= 10);
    var standard = try corpusDirectory("std");
    if (standard == 0) standard = try corpusDirectory("../std");
    try std.testing.expect(standard >= 3);
    var game = try corpusDirectory("../gdev/packages");
    game += try corpusDirectory("../gdev/src");
    if (game == 0) {
        game += try corpusDirectory("../../gdev/packages");
        game += try corpusDirectory("../../gdev/src");
    }
    if (game != 0) try std.testing.expect(game >= 20);
}
