// Separate source recognizer: rebuilds expected postorder events from the
// owned bytes and compares every tag, span and child ID, without calling the
// producer. Shared lexer is not sufficient evidence of typing or admission.
namespace flow_verify;
import lexer;
import validate;
import flow_syntax;
struct Reader { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false, depth: i64 = 0, next_id: i64 = 0, paren_end: i64 = 0, target_starts: i64[64] = [0;64], targets: i64 = 0 }
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
fn continuous(s: u8[:], r: Reader&, end: i64, opening: bool) -> bool {
    if end < 0 || end > r.t.start || r.t.start > s.len { return false; }
    let depth = r.lex.delimiter_depth - (if opening { 1 } else { 0 });
    if depth > 0 { return true; }
    for p in end..r.t.start { if s[p] == '\n' { return false; } }
    return true;
}
fn argument(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:], wrap_single: bool) -> Term {
    let start = r.t.start;
    if !word(s,r,5,"(") { return Term {}; }
    if text(s,r.t,5,")") {
        let end = r.t.end; r.paren_end = end; bump(s,r);
        return event(r,nodes,flow_syntax::Node { tag: 12, start: start, end: end });
    }
    var list = disjunction(s,r,nodes); var count: i64 = 1;
    while !r.bad && text(s,r.t,5,",") {
        bump(s,r); let item = disjunction(s,r,nodes);
        list = event(r,nodes,flow_syntax::Node { tag: 13, start: list.start, end: item.end, a: list.id, b: item.id });
        count += 1;
    }
    let end = r.t.end; r.paren_end = end;
    if !word(s,r,5,")") { return Term {}; }
    if count > 1 { return event(r,nodes,flow_syntax::Node { tag: 14, start: start, end: end, a: list.id }); }
    if wrap_single { return event(r,nodes,flow_syntax::Node { tag: 5, start: start, end: end, a: list.id }); }
    return list;
}
fn atom(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    if !open(r) { return Term {}; }
    let t = r.t; var x = Term {};
    if text(s,t,1,"do") {
        bump(s,r);
        if !word(s,r,5,":") || !consume(s,r,6) || !consume(s,r,7) || r.targets >= 64 { r.bad = true; }
        else {
            r.target_starts[r.targets] = t.start+1; r.targets += 1;
            let body = read_suite(s,r,nodes); r.targets -= 1;
            if consume(s,r,8) { x = event(r,nodes,flow_syntax::Node { tag: 15, start: t.start, end: body.end, a: body.id }); }
        }
    } else if t.kind == 1 && t.start >= 0 && t.end > t.start && t.end <= s.len && validate::name_valid(s[t.start..t.end]) {
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
        x = argument(s,r,nodes,true);
    } else { r.bad = true; }
    while !r.bad && text(s,r.t,5,"(") && continuous(s,r,x.end,true) {
        let arg = argument(s,r,nodes,false); let end = r.paren_end;
        if r.bad { break; }
        x = event(r,nodes,flow_syntax::Node { tag: 6, start: x.start, end: end, a: x.id, b: arg.id });
    }
    r.depth -= 1; return x;
}
fn and_expr(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    var l = atom(s,r,nodes);
    while !r.bad && text(s,r.t,5,"&&") && continuous(s,r,l.end,false) { bump(s,r); let right = atom(s,r,nodes); l = event(r,nodes,flow_syntax::Node { tag: 7, start: l.start, end: right.end, a: l.id, b: right.id }); }
    return l;
}
recursive fn disjunction(s: u8[:], r: Reader&, nodes: flow_syntax::Node[:]) -> Term {
    var l = and_expr(s,r,nodes);
    while !r.bad && text(s,r.t,5,"||") && continuous(s,r,l.end,false) { bump(s,r); let right = and_expr(s,r,nodes); l = event(r,nodes,flow_syntax::Node { tag: 8, start: l.start, end: right.end, a: l.id, b: right.id }); }
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
    if text(s,t,1,"return") || text(s,t,1,"break") {
        let is_break = text(s,t,1,"break");
        if is_break && r.targets == 0 { r.bad = true; return Term {}; }
        bump(s,r); let e = disjunction(s,r,nodes);
        if r.t.kind == 6 { bump(s,r); }
        else if r.t.kind != 8 && r.t.kind != 0 {
            var newline = false;
            if e.end < 0 || e.end > r.t.start || r.t.start > s.len { r.bad = true; }
            else { for p in e.end..r.t.start { if s[p] == '\n' { newline = true; } } }
            if !newline { r.bad = true; }
        }
        return event(r,nodes,flow_syntax::Node { tag: if is_break { 16 } else { 9 }, start: t.start, end: e.end, a: e.id, b: if is_break { r.target_starts[r.targets-1] } else { 0 } });
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
