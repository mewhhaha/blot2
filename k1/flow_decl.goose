// Private whole-declaration producer. Its candidate is never authority until
// flow_decl_check independently re-recognizes header, body and annotations.
namespace flow_decl;
import lexer;
import validate;
import flow_typed;

struct Declaration {
    source: u8[] = [], name_start: i64 = 0, name_end: i64 = 0,
    param_start: i64 = 0, param_end: i64 = 0, body_start: i64 = 0,
    body: flow_typed::Program = flow_typed::Program {}
}
struct Result { status: i64 = 0, decl: Declaration = Declaration {} }
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false }
fn advance(s: u8[:], c: Cursor&) { if !c.bad { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.bad = true; } } }
fn take(s: u8[:], c: Cursor&, kind: i64, word: u8[:]) -> bool {
    if c.bad || c.token.kind != kind || c.token.start < 0 || c.token.end <= c.token.start || c.token.end > s.len || s[c.token.start..c.token.end] != word { c.bad = true; return false; }
    advance(s,c); return !c.bad;
}
fn build(source: u8[:]) -> Result {
    var c = Cursor { state: lexer::init(source) }; advance(source,c);
    while !c.bad && c.token.kind == 6 { advance(source,c); }
    if !take(source,c,1,"let") { return Result { status: 1 }; }
    let name = c.token;
    if c.bad || name.kind != 1 || name.start < 0 || name.end <= name.start || name.end > source.len || !validate::name_valid(source[name.start..name.end]) { return Result { status: 1 }; }
    advance(source,c);
    if !take(source,c,5,":") || !take(source,c,1,"Bool") || !take(source,c,5,"->") ||
       !take(source,c,1,"U32") || !take(source,c,5,"=") || !take(source,c,1,"fn") { return Result { status: 1 }; }
    let parameter = c.token;
    if c.bad || parameter.kind != 1 || parameter.start < 0 || parameter.end <= parameter.start || parameter.end > source.len || !validate::name_valid(source[parameter.start..parameter.end]) { return Result { status: 1 }; }
    advance(source,c);
    if !take(source,c,5,"=>") { return Result { status: 1 }; }
    let body = c.token;
    if c.bad || body.kind != 1 || body.start < 0 || body.end <= body.start || body.end > source.len || source[body.start..body.end] != "do" { return Result { status: 1 }; }
    let result = flow_typed::build(source[body.start..],source[name.start..name.end],source[parameter.start..parameter.end]);
    if result.status != 0 { return Result { status: 10 + result.status }; }
    return Result { decl: Declaration { source: source, name_start: name.start, name_end: name.end,
        param_start: parameter.start, param_end: parameter.end, body_start: body.start, body: copy(result.program) } };
}
