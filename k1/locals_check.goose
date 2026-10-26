// Independent source-backed recognizer for the private U32 local fixture.
// Candidate IDs, literal values, binding slots and checked-add facts are not
// trusted. Only caller-retained exact source is admitted for this experiment.
namespace locals_check;
import lexer;
import validate;
import locals_core;

struct Reader { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false, depth: i64 = 0, next_value: i64 = 0, next_binding: i64 = 0 }
struct Term { id: i64 = 0, start: i64 = 0, end: i64 = 0 }
struct Symbol { start: i64 = 0, end: i64 = 0 }
fn step(s: u8[:], r: Reader&) { if !r.bad { r.t = lexer::next(s,r.lex); if r.t.kind == 9 { r.bad = true; } } }
fn same(s: u8[:], t: lexer::Token, kind: i64, text: u8[:]) -> bool {
    return t.kind == kind && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == text;
}
fn word(s: u8[:], r: Reader&, kind: i64, text: u8[:]) -> bool {
    if r.bad || !same(s,r.t,kind,text) { r.bad = true; return false; }
    step(s,r); return !r.bad;
}
fn category(s: u8[:], r: Reader&, kind: i64) -> bool {
    if r.bad || r.t.kind != kind { r.bad = true; return false; }
    step(s,r); return !r.bad;
}
fn event(r: Reader&, p: locals_core::Program&, v: locals_core::Value) -> Term {
    if r.bad || r.next_value < 0 || r.next_value >= p.values.len { r.bad = true; return Term {}; }
    let got = p.values[r.next_value]; r.next_value += 1;
    if got.kind != v.kind || got.start != v.start || got.end != v.end || got.a != v.a || got.b != v.b || got.literal != v.literal { r.bad = true; return Term {}; }
    return Term { id: r.next_value, start: v.start, end: v.end };
}
fn open(r: Reader&) -> bool { if r.bad || r.depth >= 64 { r.bad = true; return false; } r.depth += 1; return true; }
fn identifier(s: u8[:], t: lexer::Token) -> bool {
    return t.kind == 1 && t.start >= 0 && t.end > t.start && t.end <= s.len && validate::name_valid(s[t.start..t.end]);
}
fn find(s: u8[:], t: lexer::Token, syms: Symbol[:]) -> i64 {
    if !identifier(s,t) { return -1; }
    for sym, i in syms { if s[sym.start..sym.end] == s[t.start..t.end] { return i; } }
    return -1;
}
fn atom(s: u8[:], r: Reader&, p: locals_core::Program&, syms: Symbol[:]) -> Term {
    if !open(r) { return Term {}; }
    let t = r.t; var result = Term {};
    if same(s,t,1,"U32") {
        step(s,r);
        if !word(s,r,5,".") { r.depth -= 1; return Term {}; }
        var op: i64 = 0;
        if same(s,r.t,1,"wrapping_add") { op = 4; }
        else if same(s,r.t,1,"wrapping_sub") { op = 5; }
        else if same(s,r.t,1,"wrapping_mul") { op = 6; }
        else { r.bad = true; r.depth -= 1; return Term {}; }
        step(s,r);
        if !word(s,r,5,"(") { r.depth -= 1; return Term {}; }
        let a = expression(s,r,p,syms);
        if !word(s,r,5,",") { r.depth -= 1; return Term {}; }
        let b = expression(s,r,p,syms); let end = r.t.end;
        if word(s,r,5,")") { result = event(r,p,locals_core::Value { kind: op, start: t.start, end: end, a: a.id, b: b.id }); }
    } else if t.kind == 2 {
        var n: u64 = 0;
        if t.start < 0 || t.end <= t.start || t.end > s.len { r.bad = true; }
        else {
            for i in t.start..t.end {
                let c = s[i]; if c < '0' || c > '9' { r.bad = true; break; }
                let d = (c-'0') as u64;
                if n > (4294967295-d)/10 { r.bad = true; break; }
                n = n*10+d;
            }
            step(s,r); result = event(r,p,locals_core::Value { kind: 2, start: t.start, end: t.end, literal: n as u32 });
        }
    } else if identifier(s,t) {
        let binding = find(s,t,syms);
        if binding < 0 { r.bad = true; }
        else { step(s,r); result = event(r,p,locals_core::Value { kind: 1, start: t.start, end: t.end, a: binding }); }
    } else if same(s,t,5,"(") {
        step(s,r); let inner = expression(s,r,p,syms); let end = r.t.end;
        if word(s,r,5,")") { result = event(r,p,locals_core::Value { kind: 8, start: t.start, end: end, a: inner.id }); }
    } else { r.bad = true; }
    r.depth -= 1; return result;
}
fn sum(s: u8[:], r: Reader&, p: locals_core::Program&, syms: Symbol[:]) -> Term {
    var left = atom(s,r,p,syms);
    while !r.bad && same(s,r.t,5,"+") {
        step(s,r); let right = atom(s,r,p,syms);
        if r.bad || left.id < 1 || right.id < 1 { return Term {}; }
        let a = p.values[left.id-1]; let b = p.values[right.id-1];
        let zero = (a.kind == 2 && a.literal == 0) || (b.kind == 2 && b.literal == 0);
        let fits = a.kind == 2 && b.kind == 2 && (a.literal as u64 + b.literal as u64) <= 4294967295;
        if !zero && !fits { r.bad = true; return Term {}; }
        left = event(r,p,locals_core::Value { kind: 3, start: left.start, end: right.end, a: left.id, b: right.id });
    }
    return left;
}
recursive fn expression(s: u8[:], r: Reader&, p: locals_core::Program&, syms: Symbol[:]) -> Term {
    var left = sum(s,r,p,syms);
    while !r.bad && same(s,r.t,5,"&") {
        step(s,r); let right = sum(s,r,p,syms);
        left = event(r,p,locals_core::Value { kind: 7, start: left.start, end: right.end, a: left.id, b: right.id });
    }
    return left;
}
fn line_end(s: u8[:], r: Reader&) -> bool {
    if r.bad { return false; }
    if r.t.kind == 6 { step(s,r); return !r.bad; }
    return r.t.kind == 8 || r.t.kind == 0;
}
fn return_value(s: u8[:], r: Reader&, p: locals_core::Program&, syms: Symbol[:]) -> Term {
    if !word(s,r,1,"return") { return Term {}; }
    let value = expression(s,r,p,syms);
    if !line_end(s,r) { r.bad = true; return Term {}; }
    return value;
}
fn verify(expected_source: u8[:], p: locals_core::Program&) -> bool {
    if expected_source.len > 16777216 || p.source != expected_source || p.values.len < 1 || p.values.len > 2048 || p.bindings.len > 128 { return false; }
    let s = expected_source; var r = Reader { lex: lexer::init(s) }; step(s,r);
    while !r.bad && r.t.kind == 6 { step(s,r); }
    if !word(s,r,1,"let") { return false; }
    let name = r.t;
    if !identifier(s,name) || name.start != p.name_start || name.end != p.name_end { return false; }
    step(s,r);
    if !word(s,r,5,":") || !word(s,r,1,"U32") || !word(s,r,5,"->") ||
       !word(s,r,1,"U32") || !word(s,r,5,"=") || !word(s,r,1,"fn") { return false; }
    let parameter = r.t;
    if !identifier(s,parameter) || parameter.start != p.param_start || parameter.end != p.param_end { return false; }
    var symbols: Symbol[>..] = [Symbol { start: parameter.start, end: parameter.end }];
    step(s,r);
    if !word(s,r,5,"=>") || !word(s,r,1,"do") || !word(s,r,5,":") ||
       !category(s,r,6) || !category(s,r,7) { return false; }
    while !r.bad && same(s,r.t,1,"let") {
        step(s,r); let binder = r.t;
        if !identifier(s,binder) || find(s,binder,symbols) >= 0 || r.next_binding >= 128 || r.next_binding >= p.bindings.len { return false; }
        step(s,r);
        if same(s,r.t,5,":") { step(s,r); if !word(s,r,1,"U32") { return false; } }
        if !word(s,r,5,"=") { return false; }
        let value = expression(s,r,p,symbols); if value.id == 0 || !line_end(s,r) { return false; }
        let got = p.bindings[r.next_binding]; r.next_binding += 1;
        if got.start != binder.start || got.end != binder.end || got.value != value.id { return false; }
        symbols.push(Symbol { start: binder.start, end: binder.end });
    }
    var ca: i64 = 0; var cb: i64 = 0; var yes: i64 = 0; var no: i64 = 0;
    if same(s,r.t,1,"return") {
        yes = return_value(s,r,p,symbols).id;
    } else if same(s,r.t,1,"if") {
        step(s,r); ca = expression(s,r,p,symbols).id;
        if !word(s,r,5,"<") { return false; }
        cb = expression(s,r,p,symbols).id;
        if !word(s,r,5,":") || !category(s,r,6) || !category(s,r,7) { return false; }
        yes = return_value(s,r,p,symbols).id;
        if !category(s,r,8) { return false; }
        if same(s,r.t,1,"else") {
            step(s,r); if !word(s,r,5,":") || !category(s,r,6) || !category(s,r,7) { return false; }
            no = return_value(s,r,p,symbols).id;
            if !category(s,r,8) { return false; }
        } else { no = return_value(s,r,p,symbols).id; }
    } else { return false; }
    if r.bad || yes == 0 || (ca != 0 && (cb == 0 || no == 0)) || !category(s,r,8) { return false; }
    while !r.bad && r.t.kind == 6 { step(s,r); }
    return !r.bad && r.t.kind == 0 && r.next_value == p.values.len && r.next_binding == p.bindings.len &&
        p.cond_a == ca && p.cond_b == cb && p.yes == yes && p.no == no;
}
