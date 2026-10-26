// Private source-bound rank-one generic identity subset. It accepts one
// one-line public function with one unconstrained Type binder, empty effects,
// depth 1, frame 256, and a single moved return. This is not general K1
// generic admission, work accounting, ownership analysis, or artifact authority.
namespace generic_identity;
import lexer;
import validate;

struct Body {
    status: i64 = 1,
    name_start: i64 = 0, name_end: i64 = 0,
    binder_start: i64 = 0, binder_end: i64 = 0,
    parameter_start: i64 = 0, parameter_end: i64 = 0,
    binder_count: u32 = 1, depth: u32 = 1, frame: u32 = 256,
    moved: u32 = 1, copied: u32 = 0, discarded: u32 = 0
}
struct Cursor { lex: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, status: bool = false }
fn advance(source: u8[:], c: Cursor&) { c.token = lexer::next(source, c.lex); }
fn token_bytes(source: u8[:], t: lexer::Token) -> u8[:] {
    if t.start < 0 || t.end < t.start || t.end > source.len { return source[0..0]; }
    return source[t.start..t.end];
}
fn take(source: u8[:], c: Cursor&, text: u8[:]) -> bool {
    if c.token.kind == 0 || c.token.kind >= 6 || token_bytes(source, c.token) != text { return false; }
    advance(source, c); return true;
}
fn name(source: u8[:], c: Cursor&) -> lexer::Token {
    let token = c.token;
    if token.kind != 1 || !validate::name_valid(token_bytes(source, token)) { return lexer::Token { kind: 9 }; }
    advance(source, c); return token;
}
fn parse(source: u8[:]) -> Body {
    var c = Cursor { lex: lexer::init(source) }; advance(source, c);
    if !take(source, c, "pub") || !take(source, c, "let") { return Body {}; }
    let function = name(source, c); if function.kind == 9 { return Body {}; }
    if !take(source, c, ":") || !take(source, c, "forall") || !take(source, c, "[") { return Body {}; }
    let binder = name(source, c); if binder.kind == 9 { return Body {}; }
    if !take(source, c, ":") || !take(source, c, "Type") || !take(source, c, "]") ||
       !take(source, c, "=>") || !take(source, c, "Fn") || !take(source, c, "[") ||
       !take(source, c, "static") || !take(source, c, ",") || !take(source, c, "Many") ||
       !take(source, c, ",") || !take(source, c, token_bytes(source, binder)) || !take(source, c, ",") ||
       !take(source, c, token_bytes(source, binder)) || !take(source, c, "]") || !take(source, c, "!") ||
       !take(source, c, "{") || !take(source, c, "}") || !take(source, c, "resources") ||
       !take(source, c, "{") || !take(source, c, "depth") || !take(source, c, ":") ||
       !take(source, c, "1") || !take(source, c, ",") || !take(source, c, "frame") ||
       !take(source, c, ":") || !take(source, c, "256") || !take(source, c, "}") ||
       !take(source, c, "=") || !take(source, c, "fn") { return Body {}; }
    let parameter = name(source, c); if parameter.kind == 9 { return Body {}; }
    if !take(source, c, "=>") || !take(source, c, "return") ||
       !take(source, c, token_bytes(source, parameter)) { return Body {}; }
    while c.token.kind == 6 { advance(source, c); }
    if c.token.kind != 0 { return Body {}; }
    return Body { status: 0, name_start: function.start, name_end: function.end,
        binder_start: binder.start, binder_end: binder.end,
        parameter_start: parameter.start, parameter_end: parameter.end };
}
