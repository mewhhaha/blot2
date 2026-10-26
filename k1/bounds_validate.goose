// Independent recognizer for the closed guarded-read fragment. It re-lexes the
// owned source and checks all saved spans, fallback and evidence identities
// against a separately supplied trusted fixture context and exact input.
// It shares the lexer but neither calls the producer parser nor infers an
// unknown actual function type, source binding, effect, or region authority.
namespace bounds_validate;
import lexer;
import bounds_core;
struct Cursor { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(s: u8[:], c: Cursor&) { c.t = lexer::next(s,c.lex); if c.t.kind == 9 { c.bad = true; } }
fn expect(s: u8[:], c: Cursor&, kind: i64, text: u8[:], saved: bounds_core::Span, check_span: bool) {
    let t = c.t;
    if c.bad || t.kind != kind || t.start < 0 || t.end <= t.start || t.end > s.len || s[t.start..t.end] != text ||
       (check_span && (saved.start != t.start || saved.end != t.end)) { c.bad = true; return; }
    next(s,c);
}
fn exact(s: u8[:], c: Cursor&, kind: i64, text: u8[:]) { expect(s,c,kind,text,bounds_core::Span {},false); }
fn token(s: u8[:], c: Cursor&, kind: i64) { if c.bad || c.t.kind != kind { c.bad = true; return; } next(s,c); }
fn verify(p: bounds_core::Program&, expected_source: u8[:], expected: bounds_core::Context) -> bool {
    if expected_source.len > 4096 || p.source[..] != expected_source || !bounds_core::context_valid(expected) ||
       !bounds_core::same_context(p.context,expected) ||
       !bounds_core::same_evidence(p.evidence,bounds_core::evidence_for(expected,p.branch.start,p.read_view.start)) { return false; }
    let source = p.source; var c = Cursor { lex: lexer::init(source) }; next(source,c);
    while !c.bad && c.t.kind == 6 { next(source,c); }
    expect(source,c,1,"if",p.branch,true); expect(source,c,1,"i",p.guard_index,true); exact(source,c,5,"<");
    expect(source,c,1,"v",p.guard_view,true); exact(source,c,5,"."); expect(source,c,1,"length",p.guard_length,true);
    exact(source,c,5,":"); token(source,c,6); token(source,c,7); exact(source,c,1,"return");
    expect(source,c,1,"v",p.read_view,true); exact(source,c,5,"["); expect(source,c,1,"i",p.read_index,true); exact(source,c,5,"]");
    if c.t.kind == 6 { next(source,c); } token(source,c,8);
    exact(source,c,1,"else"); exact(source,c,5,":"); token(source,c,6); token(source,c,7); exact(source,c,1,"return");
    let lit = c.t;
    if c.bad || lit.kind != 2 || lit.start < 0 || lit.end <= lit.start || lit.end > source.len ||
       p.fallback_span.start != lit.start || p.fallback_span.end != lit.end { return false; }
    var number: u64 = 0;
    for i in lit.start..lit.end {
        if source[i] < '0' || source[i] > '9' { return false; }
        let digit = (source[i]-'0') as u64;
        if number > (4294967295-digit)/10 { return false; }
        number = number*10+digit;
    }
    if number != p.fallback { return false; }
    next(source,c); if c.t.kind == 6 { next(source,c); } token(source,c,8);
    while !c.bad && c.t.kind == 6 { next(source,c); }
    return !c.bad && c.t.kind == 0;
}
