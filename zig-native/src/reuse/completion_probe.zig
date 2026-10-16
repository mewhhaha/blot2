//! One private editor probe. Original bytes and lexical owners outlive this
//! result; only its repaired source is owned here. No edit reaches a build.
const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const ast = @import("../parse/ast.zig");
const Allocator = std.mem.Allocator;

pub const Kind = enum { expression, member, selector, constructor, type_, intrinsic };
pub const Probe = struct {
    source: []u8,
    replace: ast.Span,
    prefix: []const u8,
    kind: Kind,
    marker: ast.Span,
    original_start: u32,
    original_end: u32,
    original_length: u32,

    pub fn deinit(self: Probe, a: Allocator) void {
        a.free(self.source);
    }

    pub fn originalOffset(self: Probe, offset: u32) u32 {
        if (offset <= self.marker.start) return @min(offset, self.original_start);
        if (offset < self.marker.end) return self.original_start;
        const tail = offset - self.marker.end;
        return @min(self.original_length, self.original_end +| tail);
    }

    pub fn originalSpan(self: Probe, span: ast.Span) ast.Span {
        const start = self.originalOffset(span.start);
        var end = self.originalOffset(span.end);
        if (span.end > self.marker.start and span.end <= self.marker.end)
            end = self.original_end;
        return .{ .start = start, .end = @max(start, end) };
    }
};

pub const member_marker = "__blot_editor_probe";

pub fn capture(a: Allocator, source: []const u8, position: u32) !?Probe {
    if (source.len > std.math.maxInt(u32)) return error.SourceLimit;
    if (position > source.len or (position < source.len and source[position] & 0xc0 == 0x80))
        return error.InvalidPosition;
    if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidSource;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    for (tokens.comments.items) |comment| {
        if (comment.start <= position and position <= comment.end) return null;
    }
    for (tokens.tokens.items) |token| {
        if (token.tag != .string or position <= token.start) continue;
        if (position < token.end) return null;
        if (position == token.end) {
            for (tokens.diagnostics.items) |issue| {
                if (issue.code == .string_literal and issue.start == token.start) return null;
            }
        }
    }

    var replace: ast.Span = .{ .start = position, .end = position };
    var prefix: []const u8 = "";
    var previous: ?lexer.Token = null;
    var hole = false;
    var intrinsic = false;
    for (tokens.tokens.items) |token| {
        if (token.start > position) break;
        switch (token.tag) {
            .identifier, .type_identifier, .intrinsic, .kw_true, .kw_false => {
                if (position <= token.end) {
                    replace = .{ .start = token.start, .end = token.end };
                    prefix = source[token.start..position];
                    hole = token.tag == .intrinsic and std.mem.eql(u8, token.text(source), "@hole");
                    if (hole) {
                        prefix = "";
                    } else if (token.tag == .intrinsic) {
                        intrinsic = true;
                        var start = token.start + 1;
                        if (std.mem.findScalarLast(u8, source[token.start..position], '.')) |dot|
                            start = token.start + @as(u32, @intCast(dot)) + 1;
                        replace.start = start;
                        prefix = source[start..position];
                    }
                    break;
                }
            },
            else => {},
        }
        if (token.end <= position and token.start != token.end and token.tag != .newline)
            previous = token;
    }

    var kind: Kind = .expression;
    if (intrinsic) kind = .intrinsic;
    var original_start = replace.start;
    if (!hole) if (previous) |token| {
        if (token.end == replace.start) switch (token.tag) {
            .dot => kind = .member,
            .selector => kind = .selector,
            .hash => {
                kind = .constructor;
                original_start = replace.start;
            },
            else => {},
        };
    };

    if (kind == .member) {
        var start = replace.start;
        while (start != 0) {
            const byte = source[start - 1];
            if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.') break;
            start -= 1;
        }
        if (start != 0 and source[start - 1] == '#') kind = .constructor;
    }

    var closing: [8]u8 = undefined;
    var depth: usize = 0;
    var recover = true;
    for (tokens.tokens.items) |token| switch (token.tag) {
        .l_paren, .l_bracket => {
            if (depth == closing.len) {
                recover = false;
                break;
            }
            var close: u8 = ')';
            if (token.tag == .l_bracket) close = ']';
            closing[depth] = close;
            depth += 1;
        },
        .r_paren, .r_bracket => {
            var close: u8 = ')';
            if (token.tag == .r_bracket) close = ']';
            if (depth == 0 or closing[depth - 1] != close) {
                recover = false;
                break;
            }
            depth -= 1;
        },
        else => {},
    };
    if (!recover) depth = 0;

    const marker: []const u8 = member_marker;
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    try bytes.appendSlice(a, source[0..original_start]);
    const marker_start: u32 = @intCast(bytes.items.len);
    try bytes.appendSlice(a, marker);
    const marker_end: u32 = @intCast(bytes.items.len);
    try bytes.appendSlice(a, source[replace.end..]);
    while (depth != 0) {
        depth -= 1;
        try bytes.append(a, closing[depth]);
    }
    return .{
        .source = try bytes.toOwnedSlice(a),
        .replace = replace,
        .prefix = prefix,
        .kind = kind,
        .marker = .{ .start = marker_start, .end = marker_end },
        .original_start = original_start,
        .original_end = replace.end,
        .original_length = @intCast(source.len),
    };
}

test "completion probe keeps receiver and identifier suffix while mapping later diagnostics" {
    const a = std.testing.allocator;
    const source = "const result = value.field\nconst later = wrong\n";
    const caret: u32 = @intCast(std.mem.find(u8, source, "field").? + 2);
    const probe = (try capture(a, source, caret)).?;
    defer probe.deinit(a);
    try std.testing.expectEqual(Kind.member, probe.kind);
    try std.testing.expectEqualStrings("fi", probe.prefix);
    try std.testing.expectEqualStrings("field", source[probe.replace.start..probe.replace.end]);
    try std.testing.expect(std.mem.startsWith(u8, probe.source, "const result = value."));
    const wrong: u32 = @intCast(std.mem.find(u8, probe.source, "wrong").?);
    const mapped = probe.originalSpan(.{ .start = wrong, .end = wrong + 5 });
    try std.testing.expectEqualStrings("wrong", source[mapped.start..mapped.end]);
}

test "completion probe ignores text tokens and rejects split UTF8 offsets" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(?Probe, null), try capture(a, "// text", 7));
    const unfinished = "const text = \"unfinished";
    try std.testing.expectEqual(@as(?Probe, null), try capture(a, unfinished, unfinished.len));
    try std.testing.expectEqual(@as(?Probe, null), try capture(a, "const text = \"π\"", 16));
    try std.testing.expectError(error.InvalidPosition, capture(a, "// π", 4));
    try std.testing.expectError(error.InvalidPosition, capture(a, "42", 3));
}

test "completion probe repairs bounded argument EOF and replaces an existing hole whole" {
    const a = std.testing.allocator;
    const source = "const result = take (";
    const probe = (try capture(a, source, @intCast(source.len))).?;
    defer probe.deinit(a);
    try std.testing.expectEqualStrings("const result = take (__blot_editor_probe)", probe.source);
    try std.testing.expectEqual(@as(u32, @intCast(source.len)), probe.originalOffset(@intCast(probe.source.len)));
    const existing = (try capture(a, "const result = @hole", 18)).?;
    defer existing.deinit(a);
    try std.testing.expectEqualStrings("", existing.prefix);
    try std.testing.expectEqualStrings("@hole", "const result = @hole"[existing.replace.start..existing.replace.end]);
}

fn repairBoundaryLaw(a: Allocator) !void {
    for ([_][]const u8{ "const work = ((((((((", "const work = (((((((((" }, 0..) |source, index| {
        const probe = (try capture(a, source, @intCast(source.len))).?;
        defer probe.deinit(a);
        var expected: usize = 8;
        if (index == 1) expected = 0;
        var count: usize = 0;
        for (probe.source) |byte| if (byte == ')') {
            count += 1;
        };
        try std.testing.expectEqual(expected, count);
        try std.testing.expectEqual(@as(u32, @intCast(source.len)), probe.originalOffset(@intCast(probe.source.len)));
    }
}
test "completion probe repairs exactly eight EOF delimiters with allocation-safe scratch" {
    try repairBoundaryLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, repairBoundaryLaw, .{});
}
