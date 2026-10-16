const std = @import("std");
const production = @import("lexer.zig");
const Allocator = std.mem.Allocator;
const lex = production.lex;
const Tag = production.Tag;
const Token = production.Token;
const Code = production.Code;
const integerValue = production.integerValue;
const floatBits = production.floatBits;

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

test "numeric proof intrinsic type names retain complete capitalized segments" {
    const source = "@proof.U32Eq @proof.U32Lt @proof.U32Le @proof.U32AddFits @proof.U32SubFits @proof.Index @u32.add";
    var result = try lex(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    var words = std.mem.splitScalar(u8, source, ' ');
    var index: usize = 0;
    while (words.next()) |word| : (index += 1) {
        try std.testing.expectEqual(Tag.intrinsic, result.tokens.items[index].tag);
        try std.testing.expectEqualStrings(word, result.tokens.items[index].text(source));
    }
    try std.testing.expectEqual(index + 2, result.tokens.items.len);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
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
