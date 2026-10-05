const std = @import("std");

/// Public source tokens and zero-width layout boundaries. The source remains
/// immutable; every textual token is a byte span rather than an owned string.
pub const Tag = enum(u32) {
    eof,
    identifier,
    type_identifier,
    integer,
    float,
    string,
    intrinsic,
    symbol,
    comment,
    l_paren,
    r_paren,
    l_bracket,
    r_bracket,
    l_brace,
    r_brace,
    comma,
    dot,
    selector,
    dot_dot,
    colon,
    colon_equal,
    arrow,
    fat_arrow,
    left_arrow,
    hash,
    at,
    ellipsis,
    backtick,
    tilde,
    dollar,
    star,
    caret,
    pipe,
    bang,
    equal,
    kw_import,
    kw_as,
    kw_const,
    kw_let,
    kw_type,
    kw_is,
    kw_data,
    kw_effect,
    kw_infixl,
    kw_infixr,
    kw_infix,
    kw_fn,
    kw_if,
    kw_then,
    kw_else,
    kw_do,
    kw_case,
    kw_of,
    kw_for,
    kw_in,
    kw_ever,
    kw_use,
    kw_return,
    kw_yield,
    kw_break,
    kw_complete,
    kw_true,
    kw_false,
    kw_from,
    kw_where,
    private_from,
    private_where,
    newline,
    indent,
    dedent,
};

pub const Token = struct {
    tag: Tag,
    start: u32,
    end: u32,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

comptime {
    std.debug.assert(@sizeOf(Token) == 12);
}

pub fn keyword(text: []const u8) Tag {
    const words = .{
        .{ "import", Tag.kw_import }, .{ "as", Tag.kw_as },
        .{ "const", Tag.kw_const },   .{ "let", Tag.kw_let },
        .{ "type", Tag.kw_type },     .{ "is", Tag.kw_is },
        .{ "data", Tag.kw_data },     .{ "effect", Tag.kw_effect },
        .{ "infixl", Tag.kw_infixl }, .{ "infixr", Tag.kw_infixr },
        .{ "infix", Tag.kw_infix },   .{ "fn", Tag.kw_fn },
        .{ "if", Tag.kw_if },         .{ "then", Tag.kw_then },
        .{ "else", Tag.kw_else },     .{ "do", Tag.kw_do },
        .{ "case", Tag.kw_case },     .{ "of", Tag.kw_of },
        .{ "for", Tag.kw_for },       .{ "in", Tag.kw_in },
        .{ "ever", Tag.kw_ever },     .{ "use", Tag.kw_use },
        .{ "return", Tag.kw_return }, .{ "yield", Tag.kw_yield },
        .{ "break", Tag.kw_break },   .{ "complete", Tag.kw_complete },
        .{ "True", Tag.kw_true },     .{ "False", Tag.kw_false },
    };
    inline for (words) |entry| {
        if (std.mem.eql(u8, text, entry[0])) return entry[1];
    }
    return .identifier;
}
