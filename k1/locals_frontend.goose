// Private U32 locals/branch producer; no public admission or work receipt.
namespace locals_frontend;
import lexer;
import validate;
import locals_core;

// 1 syntax/unsupported, 2 local limit, 3 unbound, 4 duplicate binding,
// 5 required AddFits not established. No status here is a qualified K1 diagnostic.
struct Cursor { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, status: i64 = 0, depth: i64 = 0 }
fn advance(s: u8[:], c: Cursor&) { if c.status == 0 { c.t = lexer::next(s,c.lex); if c.t.kind == 9 { c.status = 1; } } }
fn eq(s: u8[:], t: lexer::Token, kind: i64, value: u8[:]) -> bool {
    return t.kind == kind && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == value;
}
fn take(s: u8[:], c: Cursor&, kind: i64, value: u8[:]) -> bool {
    if c.status != 0 || !eq(s,c.t,kind,value) { if c.status == 0 { c.status = 1; } return false; }
    advance(s,c); return c.status == 0;
}
fn token_kind(s: u8[:], c: Cursor&, kind: i64) -> bool {
    if c.status != 0 || c.t.kind != kind { if c.status == 0 { c.status = 1; } return false; }
    advance(s,c); return c.status == 0;
}
fn identifier(s: u8[:], t: lexer::Token) -> bool {
    return t.kind == 1 && t.start >= 0 && t.end > t.start && t.end <= s.len && validate::name_valid(s[t.start..t.end]);
}
fn push(v: locals_core::Value[>..]&, c: Cursor&, n: locals_core::Value) -> i64 {
    if v.len >= 2048 { c.status = 2; return 0; } v.push(n); return v.len;
}
fn find(s: u8[:], t: lexer::Token, p: lexer::Token, names: locals_core::Binding[:]) -> i64 {
    if s[t.start..t.end] == s[p.start..p.end] { return 0; }
    for b, i in names { if s[t.start..t.end] == s[b.start..b.end] { return i+1; } }
    return -1;
}
fn fits(a: locals_core::Value, b: locals_core::Value) -> bool {
    if (a.kind == 2 && a.literal == 0) || (b.kind == 2 && b.literal == 0) { return true; }
    return a.kind == 2 && b.kind == 2 && (a.literal as u64) + (b.literal as u64) <= 4294967295;
}
fn atom(s: u8[:], c: Cursor&, v: locals_core::Value[>..]&, names: locals_core::Binding[:], p: lexer::Token) -> i64 {
    if c.status != 0 { return 0; }
    if c.depth >= 64 { c.status = 2; return 0; }
    c.depth += 1; let t = c.t; var out: i64 = 0;
    if t.kind == 2 {
        var number: u64 = 0;
        for ch in s[t.start..t.end] { number = number * 10 + (ch-'0') as u64; }
        advance(s,c); out = push(v,c,locals_core::Value { kind: 2, start: t.start, end: t.end, literal: number as u32 });
    } else if eq(s,t,5,"(") {
        advance(s,c); let x = expr(s,c,v,names,p); let end = c.t.end;
        if x != 0 && take(s,c,5,")") { out = push(v,c,locals_core::Value { kind: 8, start: t.start, end: end, a: x }); }
    } else if eq(s,t,1,"U32") {
        advance(s,c);
        if take(s,c,5,".") {
            var kind: i64 = 0;
            if eq(s,c.t,1,"wrapping_add") { kind = 4; }
            else if eq(s,c.t,1,"wrapping_sub") { kind = 5; }
            else if eq(s,c.t,1,"wrapping_mul") { kind = 6; }
            if kind == 0 { c.status = 1; }
            else {
                advance(s,c);
                if take(s,c,5,"(") {
                    let a = expr(s,c,v,names,p);
                    if a != 0 && take(s,c,5,",") {
                        let b = expr(s,c,v,names,p); let end = c.t.end;
                        if b != 0 && take(s,c,5,")") { out = push(v,c,locals_core::Value { kind: kind, start: t.start, end: end, a: a, b: b }); }
                    }
                }
            }
        }
    } else if identifier(s,t) {
        let id = find(s,t,p,names);
        if id < 0 { c.status = 3; }
        else { advance(s,c); out = push(v,c,locals_core::Value { kind: 1, start: t.start, end: t.end, a: id }); }
    } else { c.status = 1; }
    c.depth -= 1; return out;
}
fn sum(s: u8[:], c: Cursor&, v: locals_core::Value[>..]&, names: locals_core::Binding[:], p: lexer::Token) -> i64 {
    var left = atom(s,c,v,names,p);
    while c.status == 0 && eq(s,c.t,5,"+") {
        advance(s,c); let right = atom(s,c,v,names,p); if right == 0 || c.status != 0 { return 0; }
        if !fits(v[left-1],v[right-1]) { c.status = 5; return 0; }
        left = push(v,c,locals_core::Value { kind: 3, start: v[left-1].start, end: v[right-1].end, a: left, b: right });
    }
    return left;
}
recursive fn expr(s: u8[:], c: Cursor&, v: locals_core::Value[>..]&, names: locals_core::Binding[:], p: lexer::Token) -> i64 {
    var left = sum(s,c,v,names,p);
    while c.status == 0 && eq(s,c.t,5,"&") {
        advance(s,c); let right = sum(s,c,v,names,p); if right == 0 || c.status != 0 { return 0; }
        left = push(v,c,locals_core::Value { kind: 7, start: v[left-1].start, end: v[right-1].end, a: left, b: right });
    }
    return left;
}
fn line_end(s: u8[:], c: Cursor&) -> bool {
    if c.t.kind == 6 { return token_kind(s,c,6); }
    if c.t.kind == 8 || c.t.kind == 0 { return true; }
    c.status = 1; return false;
}
fn return_value(s: u8[:], c: Cursor&, v: locals_core::Value[>..]&, names: locals_core::Binding[:], p: lexer::Token) -> i64 {
    if !take(s,c,1,"return") { return 0; }
    let value = expr(s,c,v,names,p);
    if value == 0 || !line_end(s,c) { return 0; }
    return value;
}
fn parse(source: u8[:]) -> locals_core::Result {
    var c = Cursor { lex: lexer::init(source) }; advance(source,c);
    while c.status == 0 && c.t.kind == 6 { advance(source,c); }
    if !take(source,c,1,"let") { return locals_core::Result { status: c.status }; }
    let name = c.t; if !identifier(source,name) { return locals_core::Result { status: 1 }; } advance(source,c);
    if !take(source,c,5,":") || !take(source,c,1,"U32") || !take(source,c,5,"->") ||
       !take(source,c,1,"U32") || !take(source,c,5,"=") || !take(source,c,1,"fn") { return locals_core::Result { status: c.status }; }
    let param = c.t; if !identifier(source,param) { return locals_core::Result { status: 1 }; } advance(source,c);
    if !take(source,c,5,"=>") || !take(source,c,1,"do") || !take(source,c,5,":") ||
       !token_kind(source,c,6) || !token_kind(source,c,7) { return locals_core::Result { status: c.status }; }
    var values: locals_core::Value[>..] = []; var bindings: locals_core::Binding[>..] = [];
    while c.status == 0 && eq(source,c.t,1,"let") {
        advance(source,c); let t = c.t;
        if !identifier(source,t) { c.status = 1; break; }
        if find(source,t,param,bindings) >= 0 { c.status = 4; break; }
        if bindings.len >= 128 { c.status = 2; break; }
        advance(source,c);
        if eq(source,c.t,5,":") { advance(source,c); if !take(source,c,1,"U32") { break; } }
        if !take(source,c,5,"=") { break; }
        let value = expr(source,c,values,bindings,param);
        if value == 0 || !line_end(source,c) { break; }
        bindings.push(locals_core::Binding { start: t.start, end: t.end, value: value });
    }
    var cond_a: i64 = 0; var cond_b: i64 = 0; var yes: i64 = 0; var no: i64 = 0;
    if c.status == 0 && eq(source,c.t,1,"if") {
        advance(source,c); cond_a = expr(source,c,values,bindings,param);
        if cond_a != 0 && take(source,c,5,"<") { cond_b = expr(source,c,values,bindings,param); }
        if cond_b != 0 && take(source,c,5,":") && token_kind(source,c,6) && token_kind(source,c,7) {
            yes = return_value(source,c,values,bindings,param);
            if yes != 0 && token_kind(source,c,8) {
                if eq(source,c.t,1,"else") {
                    advance(source,c);
                    if take(source,c,5,":") && token_kind(source,c,6) && token_kind(source,c,7) {
                        no = return_value(source,c,values,bindings,param);
                        if no != 0 { token_kind(source,c,8); }
                    }
                } else { no = return_value(source,c,values,bindings,param); }
            }
        }
    } else if c.status == 0 { yes = return_value(source,c,values,bindings,param); }
    if c.status != 0 || yes == 0 || (cond_a != 0 && (cond_b == 0 || no == 0)) { return locals_core::Result { status: if c.status == 0 { 1 } else { c.status } }; }
    if !token_kind(source,c,8) { return locals_core::Result { status: c.status }; }
    while c.status == 0 && c.t.kind == 6 { advance(source,c); }
    if c.status != 0 || c.t.kind != 0 { return locals_core::Result { status: if c.status == 0 { 1 } else { c.status } }; }
    return locals_core::Result { program: locals_core::Program { source: source, name_start: name.start, name_end: name.end,
        param_start: param.start, param_end: param.end, values: values, bindings: bindings,
        cond_a: cond_a, cond_b: cond_b, yes: yes, no: no } };
}
