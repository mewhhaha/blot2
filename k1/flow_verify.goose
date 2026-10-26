// Separate source recognizer: rebuilds expected postorder events from the
// owned bytes and compares every tag, span and child ID, without calling the
// producer. Shared lexer is not sufficient evidence of typing or admission.
namespace flow_verify;
import lexer;
import validate;
import flow_syntax;
struct Reader { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false, depth: i64 = 0, next_id: i64 = 0 }
struct Term { id: i64 = 0, start: i64 = 0, end: i64 = 0 }
fn bump(s: u8[:], r: Reader&) { if r.bad { return; } r.t = lexer::next(s,r.lex); if r.t.kind == 9 { r.bad = true; } }
fn text(s: u8[:], t: lexer::Token, k: i64, v: u8[:]) -> bool { return t.kind == k && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == v; }
fn word(s: u8[:], r: Reader&, k: i64, v: u8[:]) -> bool { if r.bad || !text(s,r.t,k,v) { r.bad = true; return false; } bump(s,r); return !r.bad; }
fn consume(s: u8[:], r: Reader&, k: i64) -> bool { if r.bad || r.t.kind != k { r.bad = true; return false; } bump(s,r); return !r.bad; }
fn event(r: Reader&, nodes: flow_syntax::Node[:], x: flow_syntax::Node) -> Term {
    if r.bad || r.next_id < 0 || r.next_id >= nodes.len { r.bad = true; return Term {}; }
    let n = nodes[r.next_id]; r.next_id += 1;
    if n.tag != x.tag || n.start != x.start || n.end != x.end || n.a != x.a || n.b != x.b || n.c != x.c { r.bad = true; return Term {}; }
    return Term { id: r.next_id, start: x.start, end: x.end };
}
fn open(r: Reader&) -> bool { if r.bad || r.depth >= 64 { r.bad = true; return false; } r.depth += 1; return true; }
fn atom(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    if !open(r) { return Term {}; }
    let t = r.t; var x = Term {};
    if t.kind == 1 && t.start >= 0 && t.end > t.start && t.end <= s.len && validate::name_valid(s[t.start..t.end]) {
        bump(s,r); x = event(r,nodes,flow_syntax::Node { tag: 1, start: t.start, end: t.end });
    } else if t.kind == 2 {
        var value: u64 = 0;
        for i in t.start..t.end { let digit = (s[i]-'0') as u64; if digit > 9 || value > (4294967295-digit)/10 { r.bad = true; break; } value = value * 10 + digit; }
        bump(s,r); x = event(r,nodes,flow_syntax::Node { tag: 2, start: t.start, end: t.end });
    } else if text(s,t,5,"#") {
        bump(s,r); let v = r.t;
        if v.start != t.end || (!text(s,v,1,"True") && !text(s,v,1,"False")) { r.bad = true; }
        else { bump(s,r); x = event(r,nodes,flow_syntax::Node { tag: if text(s,v,1,"True") { 4 } else { 3 }, start: t.start, end: v.end }); }
    } else if text(s,t,5,"(") {
        bump(s,r); let e = disjunction(s,r,nodes); let end = r.t.end;
        if word(s,r,5,")") { x = event(r,nodes,flow_syntax::Node { tag: 5, start: t.start, end: end, a: e.id }); }
    } else { r.bad = true; }
    while !r.bad && text(s,r.t,5,"(") {
        bump(s,r); let arg = disjunction(s,r,nodes); let end = r.t.end;
        if !word(s,r,5,")") { break; }
        x = event(r,nodes,flow_syntax::Node { tag: 6, start: x.start, end: end, a: x.id, b: arg.id });
    }
    r.depth -= 1; return x;
}
fn and_expr(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    var l = atom(s,r,nodes);
    while !r.bad && text(s,r.t,5,"&&") { bump(s,r); let right = atom(s,r,nodes); l = event(r,nodes,flow_syntax::Node { tag: 7, start: l.start, end: right.end, a: l.id, b: right.id }); }
    return l;
}
recursive fn disjunction(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    var l = and_expr(s,r,nodes);
    while !r.bad && text(s,r.t,5,"||") { bump(s,r); let right = and_expr(s,r,nodes); l = event(r,nodes,flow_syntax::Node { tag: 8, start: l.start, end: right.end, a: l.id, b: right.id }); }
    return l;
}
recursive fn read_suite(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    if !open(r) { return Term {}; }
    var list = Term {};
    while !r.bad && r.t.kind != 8 && r.t.kind != 0 {
        if r.t.kind == 6 { bump(s,r); continue; }
        let x = stmt(s,r,nodes); if r.bad { break; }
        if list.id == 0 { list = x; } else { list = event(r,nodes,flow_syntax::Node { tag: 11, start: list.start, end: x.end, a: list.id, b: x.id }); }
    }
    if list.id == 0 { r.bad = true; }
    r.depth -= 1; return list;
}
fn stmt(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    let t = r.t;
    if text(s,t,1,"return") {
        bump(s,r); let e = disjunction(s,r,nodes);
        if r.t.kind == 6 { bump(s,r); } else if r.t.kind != 8 && r.t.kind != 0 { r.bad = true; }
        return event(r,nodes,flow_syntax::Node { tag: 9, start: t.start, end: e.end, a: e.id });
    }
    if text(s,t,1,"if") {
        bump(s,r); let cond = disjunction(s,r,nodes);
        if !word(s,r,5,":") || !consume(s,r,6) || !consume(s,r,7) { return Term {}; }
        let yes = read_suite(s,r,nodes); if !consume(s,r,8) { return Term {}; }
        var no = Term {};
        if text(s,r.t,1,"else") { bump(s,r); if !word(s,r,5,":") || !consume(s,r,6) || !consume(s,r,7) { return Term {}; } no = read_suite(s,r,nodes); if !consume(s,r,8) { return Term {}; } }
        return event(r,nodes,flow_syntax::Node { tag: 10, start: t.start, end: if no.id != 0 { no.end } else { yes.end }, a: cond.id, b: yes.id, c: no.id });
    }
    r.bad = true; return Term {};
}
fn verify(tree: flow_syntax::Tree&) -> bool {
    if tree.nodes.len < 1 || tree.nodes.len > 2048 || tree.source.len > 16777216 { return false; }
    let s = tree.source; var r = Reader { lex: lexer::init(s) }; bump(s,r);
    while !r.bad && r.t.kind == 6 { bump(s,r); }
    if !word(s,r,1,"do") || !word(s,r,5,":") || !consume(s,r,6) || !consume(s,r,7) { return false; }
    let x = read_suite(s,r,tree.nodes); if !consume(s,r,8) { return false; }
    while !r.bad && r.t.kind == 6 { bump(s,r); }
    return !r.bad && r.t.kind == 0 && x.id == tree.root && r.next_id == tree.nodes.len;
}
