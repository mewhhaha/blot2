// Private producer for a two-guard K1 source fixture with three U32 inputs.
// This is candidate data only; facts_source_check independently re-lexes it.
namespace facts_source;
import lexer;
import frontend;
struct Span { start: i64 = 0, end: i64 = 0 }
struct Guard { left: u32 = 0, right: u32 = 0, strict: bool = false }
struct Program { source: u8[] = [], function: Span = Span {}, names: Span[3] = [Span {};3], guards: Guard[2] = [Guard {};2] }
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(s: u8[:], c: Cursor&) { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.bad = true; } }
fn take(s: u8[:], c: Cursor&, kind: i64, value: u8[:]) -> Span {
    let t = c.token;
    if c.bad || t.kind != kind || t.start < 0 || t.end < t.start || t.end > s.len ||
       (value.len > 0 && s[t.start..t.end] != value) { c.bad = true; return Span {}; }
    next(s,c); return Span { start: t.start, end: t.end };
}
fn name(s: u8[:], c: Cursor&) -> Span {
    let x=take(s,c,1,"");
    if x.start < 0 || x.end <= x.start || x.end > s.len || frontend::reserved(s[x.start..x.end]) { c.bad = true; return Span {}; }
    return x;
}
fn eq(s: u8[:], a: Span, b: Span) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len && s[a.start..a.end] == s[b.start..b.end];
}
fn id(s: u8[:], names: Span[3], x: Span) -> u32 {
    for i in 3 { if eq(s,names[i],x) { return (i + 1) as u32; } }
    return 0;
}
fn parse_guard(s: u8[:], c: Cursor&, names: Span[3]) -> Guard {
    let l = name(s,c); let op = c.token;
    var strict = false;
    if op.kind == 5 && op.start >= 0 && op.end <= s.len && s[op.start..op.end] == "<" { strict = true; take(s,c,5,"<"); }
    else { take(s,c,5,"<="); }
    let r = name(s,c);
    let a = id(s,names,l); let b = id(s,names,r);
    if a == 0 || b == 0 || a == b { c.bad = true; }
    return Guard { left: a, right: b, strict: strict };
}
fn parse(s: u8[:]) -> Program, i64 {
    if s.len > 4096 { return Program {}, 2; }
    var c = Cursor { state: lexer::init(s) }; next(s,c);
    take(s,c,1,"let"); let function = name(s,c); take(s,c,5,":"); take(s,c,5,"(");
    take(s,c,1,"U32"); take(s,c,5,","); take(s,c,1,"U32"); take(s,c,5,","); take(s,c,1,"U32");
    take(s,c,5,")"); take(s,c,5,"->"); take(s,c,1,"U32"); take(s,c,5,"="); take(s,c,1,"fn"); take(s,c,5,"(");
    let a = name(s,c); take(s,c,5,","); let b = name(s,c); take(s,c,5,","); let d = name(s,c); take(s,c,5,")");
    let names = [a,b,d];
    take(s,c,5,"=>"); take(s,c,1,"do"); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,"");
    take(s,c,1,"if"); let outer = parse_guard(s,c,names); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,"");
    take(s,c,1,"if"); let inner = parse_guard(s,c,names); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,"");
    take(s,c,5,"("); take(s,c,5,")"); take(s,c,6,""); take(s,c,8,"");
    take(s,c,1,"else"); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,""); take(s,c,5,"("); take(s,c,5,")");
    take(s,c,6,""); take(s,c,8,""); take(s,c,1,"return"); let inner_join = name(s,c);
    take(s,c,6,""); take(s,c,8,"");
    take(s,c,1,"else"); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,""); take(s,c,1,"return"); let outer_false = name(s,c);
    if c.token.kind == 6 { take(s,c,6,""); }
    take(s,c,8,""); take(s,c,8,""); take(s,c,0,"");
    if c.bad || !eq(s,inner_join,a) || !eq(s,outer_false,d) { return Program {}, 1; }
    for i in 3 { if eq(s,function,names[i]) { return Program {},1; } for j in i { if eq(s,names[i],names[j]) { return Program {},1; } } }
    return Program { source: s, function: function, names: names, guards: [outer,inner] }, 0;
}
