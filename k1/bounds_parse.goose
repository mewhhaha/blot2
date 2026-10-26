// Deliberately narrow parser for one source fragment under the fixture's
// predeclared `v: View<...,U32,...>` and `i: U32` environment. It rejects all
// other fragments instead of promising full K1 function or proof admission.
namespace bounds_parse;
import lexer;
import bounds_core;
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false }
fn advance(s: u8[:], c: Cursor&) { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.bad = true; } }
fn take(s: u8[:], c: Cursor&, kind: i64, text: u8[:]) -> bounds_core::Span {
    let t = c.token;
    if c.bad || t.kind != kind || t.start < 0 || t.end <= t.start || t.end > s.len || s[t.start..t.end] != text {
        c.bad = true; return bounds_core::Span {};
    }
    advance(s,c); return bounds_core::Span { start: t.start, end: t.end };
}
fn token_kind(s: u8[:], c: Cursor&, kind: i64) {
    if c.bad || c.token.kind != kind { c.bad = true; return; }
    advance(s,c);
}
fn number(s: u8[:], c: Cursor&) -> bounds_core::Span, u32 {
    let t = c.token;
    if c.bad || t.kind != 2 || t.start < 0 || t.end <= t.start || t.end > s.len { c.bad = true; return bounds_core::Span {},0; }
    var value: u64 = 0;
    for p in t.start..t.end {
        if s[p] < '0' || s[p] > '9' { c.bad = true; return bounds_core::Span {},0; }
        let d = (s[p] - '0') as u64;
        if value > (4294967295-d)/10 { c.bad = true; return bounds_core::Span {},0; }
        value = value*10+d;
    }
    advance(s,c); return bounds_core::Span { start: t.start, end: t.end },value as u32;
}
// 0 success, 1 unsupported/invalid syntax or fixture context, 2 source limit.
fn parse(source: u8[:], context: bounds_core::Context) -> bounds_core::Program, i64 {
    if source.len > 4096 { return bounds_core::Program {},2; }
    if !bounds_core::context_valid(context) { return bounds_core::Program {},1; }
    var c = Cursor { state: lexer::init(source) }; advance(source,c);
    while !c.bad && c.token.kind == 6 { advance(source,c); }
    let branch = take(source,c,1,"if");
    let gi = take(source,c,1,"i"); let _ = take(source,c,5,"<");
    let gv = take(source,c,1,"v"); let _ = take(source,c,5,"."); let gl = take(source,c,1,"length");
    let _ = take(source,c,5,":"); token_kind(source,c,6); token_kind(source,c,7);
    let _ = take(source,c,1,"return"); let rv = take(source,c,1,"v");
    let _ = take(source,c,5,"["); let ri = take(source,c,1,"i"); let _ = take(source,c,5,"]");
    if c.token.kind == 6 { advance(source,c); } token_kind(source,c,8);
    let _ = take(source,c,1,"else"); let _ = take(source,c,5,":");
    token_kind(source,c,6); token_kind(source,c,7); let _ = take(source,c,1,"return");
    let literal, value = number(source,c);
    if c.token.kind == 6 { advance(source,c); } token_kind(source,c,8);
    while !c.bad && c.token.kind == 6 { advance(source,c); }
    if c.bad || c.token.kind != 0 { return bounds_core::Program {},1; }
    let evidence = bounds_core::evidence_for(context,branch.start,rv.start);
    return bounds_core::Program { source: source, context: context, evidence: evidence, branch: branch,
        guard_index: gi, guard_view: gv, guard_length: gl, read_view: rv, read_index: ri,
        fallback_span: literal, fallback: value },0;
}
