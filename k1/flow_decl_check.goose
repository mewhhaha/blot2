// Re-recognizes the complete owned source, then checks exact association of
// the typed body and both names. The producer's offsets are only candidates.
namespace flow_decl_check;
import lexer;
import validate;
import flow_decl;
import flow_typed_check;

struct Reader { lex: lexer::State = lexer::State {}, next: lexer::Token = lexer::Token {}, invalid: bool = false }
fn step(s: u8[:], r: Reader&) { if !r.invalid { r.next = lexer::next(s,r.lex); if r.next.kind == 9 { r.invalid = true; } } }
fn expect(s: u8[:], r: Reader&, k: i64, v: u8[:]) -> bool {
    let t = r.next;
    if r.invalid || t.kind != k || t.start < 0 || t.end <= t.start || t.end > s.len || s[t.start..t.end] != v { r.invalid = true; return false; }
    step(s,r); return !r.invalid;
}
fn verify(d: flow_decl::Declaration&) -> bool {
    if d.source.len > 16777216 { return false; }
    let s = d.source; var r = Reader { lex: lexer::init(s) }; step(s,r);
    while !r.invalid && r.next.kind == 6 { step(s,r); }
    if !expect(s,r,1,"let") { return false; }
    let name = r.next;
    if r.invalid || name.kind != 1 || name.start < 0 || name.end <= name.start || name.end > s.len ||
       !validate::name_valid(s[name.start..name.end]) || name.start != d.name_start || name.end != d.name_end { return false; }
    step(s,r);
    if !expect(s,r,5,":") || !expect(s,r,1,"Bool") || !expect(s,r,5,"->") ||
       !expect(s,r,1,"U32") || !expect(s,r,5,"=") || !expect(s,r,1,"fn") { return false; }
    let param = r.next;
    if r.invalid || param.kind != 1 || param.start < 0 || param.end <= param.start || param.end > s.len ||
       !validate::name_valid(s[param.start..param.end]) || param.start != d.param_start || param.end != d.param_end { return false; }
    step(s,r); if !expect(s,r,5,"=>") { return false; }
    let body = r.next;
    if r.invalid || body.kind != 1 || body.start < 0 || body.end <= body.start || body.end > s.len ||
       s[body.start..body.end] != "do" || body.start != d.body_start { return false; }
    if d.body.name != s[name.start..name.end] || d.body.parameter != s[param.start..param.end] ||
       d.body.tree.source != s[body.start..] { return false; }
    return flow_typed_check::verify(d.body);
}
