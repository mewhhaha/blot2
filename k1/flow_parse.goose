// Private, unmetered syntax prototype; see FLOW_SCHEMA.md.
namespace flow_parse;
import lexer;
import validate;
import flow_syntax;
struct Cursor { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, status: i64 = 0, depth: i64 = 0, paren_end: i64 = 0, targets: i64[64] = [0;64], target_depth: i64 = 0 }
fn advance(s: u8[:], c: Cursor&) { if c.status != 0 { return; } c.t = lexer::next(s,c.lex); if c.t.kind == 9 { c.status = c.t.status; } }
fn equals(s: u8[:], t: lexer::Token, k: i64, v: u8[:]) -> bool { return t.kind == k && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == v; }
fn take(s: u8[:], c: Cursor&, k: i64, v: u8[:]) -> bool { if c.status != 0 { return false; } if !equals(s,c.t,k,v) { c.status = 1; return false; } advance(s,c); return c.status == 0; }
fn kind(s: u8[:], c: Cursor&, k: i64) -> bool { if c.status != 0 { return false; } if c.t.kind != k { c.status = 1; return false; } advance(s,c); return c.status == 0; }
fn push(n: flow_syntax::Node[>..]&, c: Cursor&, item: flow_syntax::Node) -> i64 { if n.len >= 2048 { c.status = 2; return 0; } n.push(item); return n.len; }
fn enter(c: Cursor&) -> bool { if c.depth >= 64 { c.status = 2; return false; } c.depth += 1; return true; }
// A suite's DEDENT has already consumed its last newline. Prevent the next
// physical line from becoming a call or infix continuation, except inside a
// still-open delimiter where K1 treats newlines as whitespace. The lexer has
// already counted a current '(' token, so exclude that token from the depth.
fn joins(s: u8[:], c: Cursor&, end: i64, current_opens: bool) -> bool {
    if end < 0 || end > c.t.start || c.t.start > s.len { return false; }
    let depth = c.lex.delimiter_depth - (if current_opens { 1 } else { 0 });
    if depth > 0 { return true; }
    for p in end..c.t.start { if s[p] == '\n' { return false; } }
    return true;
}
// Parse one parenthesized argument value. Parentheses around a single value
// are retained for a standalone expression but not as a call argument.
fn parens(s: u8[:], c: Cursor&, n: flow_syntax::Node[>..]&, group_single: bool) -> i64 {
    let start = c.t.start;
    if !take(s,c,5,"(") { return 0; }
    if equals(s,c.t,5,")") {
        let end = c.t.end; c.paren_end = end; advance(s,c);
        return push(n,c,flow_syntax::Node { tag: 12, start: start, end: end });
    }
    var items = expr(s,c,n); if items == 0 || c.status != 0 { return 0; }
    var tuple = false;
    while equals(s,c.t,5,",") {
        tuple = true; advance(s,c);
        let item = expr(s,c,n); if item == 0 || c.status != 0 { return 0; }
        items = push(n,c,flow_syntax::Node { tag: 13, start: n[items-1].start, end: n[item-1].end, a: items, b: item });
    }
    let end = c.t.end; c.paren_end = end; if !take(s,c,5,")") { return 0; }
    if tuple { return push(n,c,flow_syntax::Node { tag: 14, start: start, end: end, a: items }); }
    if group_single { return push(n,c,flow_syntax::Node { tag: 5, start: start, end: end, a: items }); }
    return items;
}
fn primary(s: u8[:], c: Cursor&, n: flow_syntax::Node[>..]&) -> i64 {
    if c.status != 0 || !enter(c) { return 0; }
    var id: i64 = 0; let t = c.t;
    if equals(s,t,1,"do") {
        advance(s,c);
        if !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) || c.target_depth >= 64 { c.status = if c.status == 0 { 2 } else { c.status }; }
        else {
            c.targets[c.target_depth] = t.start + 1; c.target_depth += 1;
            let body = suite(s,c,n); c.target_depth -= 1;
            if body != 0 && kind(s,c,8) { id = push(n,c,flow_syntax::Node { tag: 15, start: t.start, end: n[body-1].end, a: body }); }
        }
    } else if t.kind == 1 && t.start >= 0 && t.end > t.start && t.end <= s.len && validate::name_valid(s[t.start..t.end]) {
        advance(s,c); id = push(n,c,flow_syntax::Node { tag: 1, start: t.start, end: t.end });
    } else if t.kind == 2 {
        var x: u64 = 0;
        for i in t.start..t.end { let d = (s[i] - '0') as u64; if d > 9 || x > (4294967295 - d) / 10 { c.status = 1; break; } x = x * 10 + d; }
        if c.status == 0 { advance(s,c); id = push(n,c,flow_syntax::Node { tag: 2, start: t.start, end: t.end }); }
    } else if equals(s,t,5,"#") {
        advance(s,c); let b = c.t;
        if b.start != t.end || (!equals(s,b,1,"True") && !equals(s,b,1,"False")) { c.status = 1; }
        else { advance(s,c); id = push(n,c,flow_syntax::Node { tag: if equals(s,b,1,"True") { 4 } else { 3 }, start: t.start, end: b.end }); }
    } else if equals(s,t,5,"(") {
        id = parens(s,c,n,true);
    } else { c.status = 1; }
    while c.status == 0 && equals(s,c.t,5,"(") && joins(s,c,n[id-1].end,true) {
        let arg = parens(s,c,n,false); if arg == 0 || c.status != 0 { break; }
        let end = c.paren_end;
        id = push(n,c,flow_syntax::Node { tag: 6, start: n[id-1].start, end: end, a: id, b: arg });
    }
    c.depth -= 1; return id;
}
fn conjunction(s: u8[:], c: Cursor&, n: flow_syntax::Node[>..]&) -> i64 {
    var left = primary(s,c,n);
    while c.status == 0 && equals(s,c.t,5,"&&") && joins(s,c,n[left-1].end,false) {
        advance(s,c); let right = primary(s,c,n); if right == 0 || c.status != 0 { return 0; }
        left = push(n,c,flow_syntax::Node { tag: 7, start: n[left-1].start, end: n[right-1].end, a: left, b: right });
    }
    return left;
}
recursive fn expr(s: u8[:], c: Cursor&, n: flow_syntax::Node[>..]&) -> i64 {
    var left = conjunction(s,c,n);
    while c.status == 0 && equals(s,c.t,5,"||") && joins(s,c,n[left-1].end,false) {
        advance(s,c); let right = conjunction(s,c,n); if right == 0 || c.status != 0 { return 0; }
        left = push(n,c,flow_syntax::Node { tag: 8, start: n[left-1].start, end: n[right-1].end, a: left, b: right });
    }
    return left;
}
recursive fn suite(s: u8[:], c: Cursor&, n: flow_syntax::Node[>..]&) -> i64 {
    if !enter(c) { return 0; }
    var list: i64 = 0;
    while c.status == 0 && c.t.kind != 8 && c.t.kind != 0 {
        if c.t.kind == 6 { advance(s,c); continue; }
        let st = statement(s,c,n); if st == 0 || c.status != 0 { break; }
        if list == 0 { list = st; } else { list = push(n,c,flow_syntax::Node { tag: 11, start: n[list-1].start, end: n[st-1].end, a: list, b: st }); }
    }
    if list == 0 && c.status == 0 { c.status = 1; }
    c.depth -= 1; return list;
}
fn statement(s: u8[:], c: Cursor&, n: flow_syntax::Node[>..]&) -> i64 {
    let t = c.t;
    if equals(s,t,1,"return") || equals(s,t,1,"break") {
        let is_break = equals(s,t,1,"break");
        if is_break && c.target_depth == 0 { c.status = 6; return 0; }
        advance(s,c);
        if is_break && (c.t.kind == 6 || c.t.kind == 8 || c.t.kind == 0) { c.status = 6; return 0; }
        let value = expr(s,c,n); if c.status != 0 || value == 0 { return 0; }
        let end = n[value-1].end;
        if c.t.kind == 6 { advance(s,c); }
        else if c.t.kind != 8 && c.t.kind != 0 {
            var newline = false;
            if end < 0 || end > c.t.start || c.t.start > s.len { c.status = 1; return 0; }
            for p in end..c.t.start { if s[p] == '\n' { newline = true; } }
            if !newline { c.status = 1; return 0; }
        }
        return push(n,c,flow_syntax::Node { tag: if is_break { 16 } else { 9 }, start: t.start, end: end, a: value, b: if is_break { c.targets[c.target_depth-1] } else { 0 } });
    }
    if equals(s,t,1,"if") {
        advance(s,c); let cond = expr(s,c,n);
        if cond == 0 || !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) { return 0; }
        let yes = suite(s,c,n); if yes == 0 || !kind(s,c,8) { return 0; }
        var no: i64 = 0;
        if equals(s,c.t,1,"else") {
            advance(s,c); if !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) { return 0; }
            no = suite(s,c,n); if no == 0 || !kind(s,c,8) { return 0; }
        }
        let end = if no != 0 { n[no-1].end } else { n[yes-1].end };
        return push(n,c,flow_syntax::Node { tag: 10, start: t.start, end: end, a: cond, b: yes, c: no });
    }
    c.status = 1; return 0;
}
// Parse a function-body suite only, including its do: header. Error returns an
// empty tree. Unsupported constructs deliberately receive syntax status 1.
fn parse(s: u8[:]) -> flow_syntax::Tree, i64 {
    var c = Cursor { lex: lexer::init(s) }; var nodes: flow_syntax::Node[>..] = [];
    advance(s,c); while c.t.kind == 6 && c.status == 0 { advance(s,c); }
    if !take(s,c,1,"do") || !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) { return flow_syntax::Tree {}, c.status; }
    let root = suite(s,c,nodes); if root == 0 || !kind(s,c,8) { return flow_syntax::Tree {}, c.status; }
    while c.t.kind == 6 && c.status == 0 { advance(s,c); }
    if c.status != 0 || c.t.kind != 0 { return flow_syntax::Tree {}, if c.status == 0 { 1 } else { c.status }; }
    return flow_syntax::Tree { source: s, nodes: nodes, root: root }, 0;
}
