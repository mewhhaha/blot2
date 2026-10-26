// Deliberately narrow expression parser for one predeclared record `p` with
// four F32 fields and an F32 variable `dt`. Unsupported source is rejected;
// neither a full declaration nor a loop/contract is parsed here.
namespace particle_expr_parse;
import lexer;
import particle_expr_core;
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, status: i64 = 0, depth: i64 = 0 }
fn advance(s: u8[:], c: Cursor&) { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.status = 1; } }
fn is(s: u8[:], t: lexer::Token, kind: i64, value: u8[:]) -> bool {
    return t.kind == kind && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == value;
}
fn push(nodes: particle_expr_core::Node[>..]&, c: Cursor&, n: particle_expr_core::Node) -> i64 {
    if nodes.len >= 256 { c.status = 2; return 0; }
    nodes.push(n); return nodes.len;
}
fn atom(s: u8[:], c: Cursor&, nodes: particle_expr_core::Node[>..]&) -> i64 {
    if c.status != 0 { return 0; }
    let t = c.token;
    if is(s,t,1,"dt") { advance(s,c); return push(nodes,c,particle_expr_core::Node { kind: 5, start: t.start, end: t.end }); }
    if is(s,t,1,"p") {
        advance(s,c);
        if !is(s,c.token,5,".") { c.status = 1; return 0; }
        advance(s,c); let field = c.token;
        var k: i64 = 0;
        if is(s,field,1,"x") { k = 1; } else if is(s,field,1,"y") { k = 2; }
        else if is(s,field,1,"vx") { k = 3; } else if is(s,field,1,"vy") { k = 4; }
        else { c.status = 1; return 0; }
        advance(s,c); return push(nodes,c,particle_expr_core::Node { kind: k, start: t.start, end: field.end });
    }
    if is(s,t,5,"(") {
        if c.depth >= 32 { c.status = 2; return 0; }
        c.depth += 1; advance(s,c);
        let value = expr(s,c,nodes);
        if c.status != 0 { c.depth -= 1; return 0; }
        if !is(s,c.token,5,")") { c.status = 1; c.depth -= 1; return 0; }
        advance(s,c); c.depth -= 1; return value;
    }
    c.status = 1; return 0;
}
fn term(s: u8[:], c: Cursor&, nodes: particle_expr_core::Node[>..]&) -> i64 {
    var lhs = atom(s,c,nodes);
    while c.status == 0 && is(s,c.token,5,"*") {
        let op = c.token; advance(s,c); let rhs = atom(s,c,nodes);
        if rhs == 0 { return 0; }
        lhs = push(nodes,c,particle_expr_core::Node { kind: 6, start: op.start, end: op.end, left: lhs, right: rhs });
    }
    return lhs;
}
recursive fn expr(s: u8[:], c: Cursor&, nodes: particle_expr_core::Node[>..]&) -> i64 {
    var lhs = term(s,c,nodes);
    while c.status == 0 && is(s,c.token,5,"+") {
        let op = c.token; advance(s,c); let rhs = term(s,c,nodes);
        if rhs == 0 { return 0; }
        lhs = push(nodes,c,particle_expr_core::Node { kind: 7, start: op.start, end: op.end, left: lhs, right: rhs });
    }
    return lhs;
}
// Status 0 success, 1 unsupported/invalid syntax, 2 private implementation limit.
fn parse(s: u8[:]) -> particle_expr_core::Core, i64 {
    if s.len > 4096 { return particle_expr_core::Core {}, 2; }
    var c = Cursor { state: lexer::init(s) }; advance(s,c);
    var nodes: particle_expr_core::Node[>..] = [];
    let root = expr(s,c,nodes);
    while c.status == 0 && c.token.kind == 6 { advance(s,c); }
    if c.status != 0 || c.token.kind != 0 || root == 0 { return particle_expr_core::Core {}, if c.status == 2 { 2 } else { 1 }; }
    return particle_expr_core::Core { source: s, nodes: copy(nodes), result: root }, 0;
}
