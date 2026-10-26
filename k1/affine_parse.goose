// Source producer only; ownership, scope, control and authority are checked
// separately. Fixed identifiers deliberately limit the supported language.
namespace affine_parse;
import lexer;
import affine_syntax;
struct Cursor { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, status: i64 = 0, depth: i64 = 0, previous: i64 = 0 }
fn step(s: u8[:], c: Cursor&) { if c.status == 0 { c.previous = c.t.end; c.t = lexer::next(s,c.lex); if c.t.kind == 9 { c.status = 1; } } }
fn eq(s: u8[:], t: lexer::Token, k: i64, v: u8[:]) -> bool {
    return t.kind == k && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == v;
}
fn word(s: u8[:], c: Cursor&, k: i64, v: u8[:]) -> bool {
    if c.status != 0 || !eq(s,c.t,k,v) { c.status = 1; return false; } step(s,c); return c.status == 0;
}
fn kind(s: u8[:], c: Cursor&, k: i64) -> bool {
    if c.status != 0 || c.t.kind != k { c.status = 1; return false; } step(s,c); return c.status == 0;
}
fn owner(s: u8[:], c: Cursor&) -> i64 {
    var id: i64 = 0;
    if eq(s,c.t,1,"h") { id = 1; } else if eq(s,c.t,1,"m") { id = 2; }
    if id == 0 { c.status = 1; return 0; } step(s,c); return id;
}
fn push(nodes: affine_syntax::Node[>..]&, c: Cursor&, n: affine_syntax::Node) -> i64 {
    if nodes.len >= 256 { c.status = 2; return 0; } nodes.push(n); return nodes.len;
}
fn line(s: u8[:], c: Cursor&) -> bool {
    if c.t.kind == 6 { return kind(s,c,6); }
    return c.t.kind == 8 || c.t.kind == 0;
}
recursive fn suite(s: u8[:], c: Cursor&, nodes: affine_syntax::Node[>..]&) -> i64 {
    if c.depth >= 32 { c.status = 2; return 0; } c.depth += 1;
    var seq: i64 = 0;
    while c.status == 0 && c.t.kind != 8 && c.t.kind != 0 {
        if c.t.kind == 6 { step(s,c); continue; }
        let node = stmt(s,c,nodes); if node == 0 { break; }
        if seq == 0 { seq = node; }
        else { seq = push(nodes,c,affine_syntax::Node {tag:8, start:nodes[seq-1].start, end:nodes[node-1].end, a:seq,b:node}); }
    }
    c.depth -= 1;
    if seq == 0 && c.status == 0 { c.status = 1; }
    return seq;
}
recursive fn stmt(s: u8[:], c: Cursor&, nodes: affine_syntax::Node[>..]&) -> i64 {
    let begin = c.t.start;
    if eq(s,c.t,1,"let") {
        step(s,c);
        if eq(s,c.t,1,"m") {
            step(s,c); if !word(s,c,5,"=") || !word(s,c,1,"h") { return 0; }
            let end = c.previous; if !line(s,c) { c.status=1; return 0; }
            return push(nodes,c,affine_syntax::Node {tag:1,start:begin,end:end,owner:1});
        }
        if !word(s,c,1,"value") || !word(s,c,5,"=") || !word(s,c,1,"owned") || !word(s,c,5,".") ||
           !word(s,c,1,"open") || !word(s,c,5,"(") { return 0; }
        let h = owner(s,c);
        if h == 0 || !word(s,c,5,")") || !word(s,c,1,"as") || !word(s,c,1,"r") ||
           !word(s,c,1,"payload") || !word(s,c,1,"in") || !word(s,c,1,"do") || !word(s,c,5,":") ||
           !kind(s,c,6) || !kind(s,c,7) { return 0; }
        let body = suite(s,c,nodes); if body == 0 || !kind(s,c,8) { return 0; }
        return push(nodes,c,affine_syntax::Node {tag:3,start:begin,end:nodes[body-1].end,owner:h,a:body});
    }
    if eq(s,c.t,1,"owned") {
        step(s,c); if !word(s,c,5,".") || !word(s,c,1,"close") || !word(s,c,5,"(") { return 0; }
        let h = owner(s,c); if h == 0 || !eq(s,c.t,5,")") { c.status=1; return 0; }
        let end = c.t.end; step(s,c); if !line(s,c) { c.status=1; return 0; }
        return push(nodes,c,affine_syntax::Node {tag:2,start:begin,end:end,owner:h});
    }
    if eq(s,c.t,1,"if") {
        step(s,c); if !word(s,c,1,"flag") || !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) { return 0; }
        let yes = suite(s,c,nodes); if yes == 0 || !kind(s,c,8) { return 0; }
        var no: i64 = 0;
        if eq(s,c.t,1,"else") {
            step(s,c); if !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) { return 0; }
            no = suite(s,c,nodes); if no == 0 || !kind(s,c,8) { return 0; }
        }
        return push(nodes,c,affine_syntax::Node {tag:4,start:begin,end:if no == 0 {nodes[yes-1].end} else {nodes[no-1].end},a:yes,b:no});
    }
    if eq(s,c.t,1,"return") {
        step(s,c); var tag: i64 = 5; var h: i64 = 0; var end: i64 = 0;
        if eq(s,c.t,5,"(") {
            step(s,c); if !eq(s,c.t,5,")") { c.status=1; return 0; } end=c.t.end; step(s,c);
        } else { tag=6; h=owner(s,c); if h == 0 { return 0; } end=c.previous; }
        if !line(s,c) { c.status=1; return 0; }
        return push(nodes,c,affine_syntax::Node {tag:tag,start:begin,end:end,owner:h});
    }
    if eq(s,c.t,1,"break") {
        step(s,c); if !eq(s,c.t,1,"payload") { c.status=1; return 0; }
        let end=c.t.end; step(s,c); if !line(s,c) { c.status=1; return 0; }
        return push(nodes,c,affine_syntax::Node {tag:7,start:begin,end:end});
    }
    c.status=1; return 0;
}
fn parse(s: u8[:]) -> affine_syntax::Result {
    var c=Cursor {lex:lexer::init(s)}; var nodes: affine_syntax::Node[>..]=[]; step(s,c);
    if !word(s,c,1,"do") || !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) { return affine_syntax::Result {status:c.status}; }
    let root=suite(s,c,nodes);
    if root == 0 || !kind(s,c,8) || c.status != 0 || c.t.kind != 0 { return affine_syntax::Result {status:if c.status == 0 {1} else {c.status}}; }
    return affine_syntax::Result {status:0,tree:affine_syntax::Tree {source:s,nodes:nodes,root:root}};
}
