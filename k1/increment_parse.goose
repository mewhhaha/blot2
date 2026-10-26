// Narrow untrusted producer. Only `if x < MAX: return x + 1 else: return x`
// on an explicitly U32 parameter is modeled. Verification is separate.
namespace increment_parse;
import lexer;
import frontend;
import increment_core;
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(s: u8[:], c: Cursor&) { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.bad = true; } }
fn take(s: u8[:], c: Cursor&, kind: i64, text: u8[:]) -> increment_core::Span {
    let t = c.token;
    if c.bad || t.kind != kind || t.start < 0 || t.end < t.start || t.end > s.len ||
       (text.len > 0 && s[t.start..t.end] != text) { c.bad = true; return increment_core::Span {}; }
    next(s,c); return increment_core::Span { start: t.start, end: t.end };
}
fn name(s: u8[:], c: Cursor&) -> increment_core::Span {
    let t = take(s,c,1,"");
    if t.start < 0 || t.end <= t.start || t.end > s.len || frontend::reserved(s[t.start..t.end]) { c.bad = true; return increment_core::Span {}; }
    return t;
}
fn eq(s: u8[:], a: increment_core::Span, b: increment_core::Span) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len && s[a.start..a.end] == s[b.start..b.end];
}
fn parse(s: u8[:]) -> increment_core::Core, i64 {
    if s.len > 4096 { return increment_core::Core {}, 2; }
    var c = Cursor { state: lexer::init(s) }; next(s,c);
    take(s,c,1,"let"); let function = name(s,c); take(s,c,5,":"); take(s,c,1,"U32");
    take(s,c,5,"->"); take(s,c,1,"U32"); take(s,c,5,"="); take(s,c,1,"fn"); let parameter = name(s,c);
    take(s,c,5,"=>"); take(s,c,1,"do"); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,"");
    take(s,c,1,"if"); let guard_fact = name(s,c); take(s,c,5,"<"); let limit = take(s,c,2,"4294967295");
    take(s,c,5,":"); take(s,c,6,""); take(s,c,7,""); take(s,c,1,"return"); let add = name(s,c);
    take(s,c,5,"+"); let one = take(s,c,2,"1"); take(s,c,6,""); take(s,c,8,"");
    take(s,c,1,"else"); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,""); take(s,c,1,"return"); let otherwise = name(s,c);
    if c.token.kind == 6 { take(s,c,6,""); }
    take(s,c,8,""); take(s,c,8,""); take(s,c,0,"");
    if c.bad || eq(s,function,parameter) || !eq(s,parameter,guard_fact) || !eq(s,parameter,add) || !eq(s,parameter,otherwise) { return increment_core::Core {}, 1; }
    return increment_core::Core { source: s, function: function, parameter: parameter, guard_use: guard_fact,
        limit: limit, add_use: add, one: one, else_use: otherwise,
        schema: 1, parameter_version: 1, result_version: 2, true_scope: 2, false_scope: 3 }, 0;
}
