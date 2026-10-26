// Independent recognizer for the closed private control fixture. It never
// invokes control_frontend or trusts its status, spans, or selected operations.
namespace control_validate;
import lexer;
import validate;
import control_core;

struct Reader { state: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(s: u8[:], r: Reader&) { r.t = lexer::next(s,r.state); if r.t.kind == 9 { r.bad = true; } }
fn is_token(s: u8[:], r: Reader&, kind: i64, text: u8[:]) -> bool {
    let t = r.t;
    return !r.bad && t.kind == kind && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == text;
}
fn take(s: u8[:], r: Reader&, kind: i64, text: u8[:]) -> bool {
    if !is_token(s,r,kind,text) { return false; }
    next(s,r); return !r.bad;
}
fn token_kind(s: u8[:], r: Reader&, kind: i64) -> bool {
    if r.bad || r.t.kind != kind { return false; }
    next(s,r); return !r.bad;
}
fn exact(r: Reader&, start: i64, end: i64) -> bool { return !r.bad && r.t.start == start && r.t.end == end; }
fn atom(s: u8[:], r: Reader&, p: control_core::Program, start: i64, end: i64, kind: i64) -> bool {
    if !control_core::span(start,end,s.len) || !control_core::span(p.param_start,p.param_end,s.len) { return false; }
    if !exact(r,start,if kind == 1 { end } else { start + 1 }) { return false; }
    if kind == 1 {
        if r.t.kind != 1 || s[start..end] != s[p.param_start..p.param_end] { return false; }
        next(s,r); return !r.bad;
    }
    if (kind != 2 && kind != 3) || !take(s,r,5,"#") || r.t.start != start + 1 || r.t.end != end { return false; }
    return take(s,r,1,if kind == 2 { "True" } else { "False" });
}
fn literal(s: u8[:], r: Reader&, start: i64, end: i64, expected: u32) -> bool {
    if !control_core::span(start,end,s.len) || !exact(r,start,end) || r.t.kind != 2 { return false; }
    var value: u64 = 0;
    for i in start..end {
        if s[i] < '0' || s[i] > '9' { return false; }
        let n = (s[i] - '0') as u64;
        if value > (4294967295 - n) / 10 { return false; }
        value = value * 10 + n;
    }
    if value != expected { return false; }
    next(s,r); return !r.bad;
}
fn verify(s: u8[:], p: control_core::Program) -> bool {
    if !control_core::shape(p,s.len) { return false; }
    var r = Reader { state: lexer::init(s) };
    next(s,r);
    while !r.bad && r.t.kind == 6 { next(s,r); }
    if !take(s,r,1,"let") || !exact(r,p.name_start,p.name_end) || r.t.kind != 1 ||
       !validate::name_valid(s[p.name_start..p.name_end]) { return false; }
    next(s,r);
    if !take(s,r,5,":") || !take(s,r,1,"Bool") || !take(s,r,5,"->") || !take(s,r,1,"U32") ||
       !take(s,r,5,"=") || !exact(r,p.function_start,p.function_end) || !take(s,r,1,"fn") || !exact(r,p.param_start,p.param_end) ||
       r.t.kind != 1 || !validate::name_valid(s[p.param_start..p.param_end]) { return false; }
    next(s,r);
    if !take(s,r,5,"=>") || !take(s,r,1,"do") || !take(s,r,5,":") ||
       !token_kind(s,r,6) || !token_kind(s,r,7) || !exact(r,p.if_start,p.if_end) || !take(s,r,1,"if") { return false; }
    if !atom(s,r,p,p.left_start,p.left_end,p.left_kind) { return false; }
    if p.op != 0 {
        if !exact(r,p.op_start,p.op_end) || !take(s,r,5,if p.op == 1 { "&&" } else { "||" }) ||
           !atom(s,r,p,p.right_start,p.right_end,p.right_kind) { return false; }
    }
    if !take(s,r,5,":") || !token_kind(s,r,6) || !token_kind(s,r,7) ||
       !exact(r,p.yes_return_start,p.yes_return_end) || !take(s,r,1,"return") || !literal(s,r,p.yes_start,p.yes_end,p.yes) { return false; }
    if r.t.kind == 6 { next(s,r); }
    if !token_kind(s,r,8) || !take(s,r,1,"else") || !take(s,r,5,":") ||
       !token_kind(s,r,6) || !token_kind(s,r,7) || !exact(r,p.no_return_start,p.no_return_end) || !take(s,r,1,"return") ||
       !literal(s,r,p.no_start,p.no_end,p.no) { return false; }
    if r.t.kind == 6 { next(s,r); }
    if !token_kind(s,r,8) || !token_kind(s,r,8) { return false; }
    while !r.bad && r.t.kind == 6 { next(s,r); }
    return !r.bad && r.t.kind == 0;
}
