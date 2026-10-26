// Narrow source candidate; never authority without independent validation.
namespace control_frontend;
import lexer;
import validate;
import control_core;

struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, status: i64 = 0 }
fn advance(s: u8[:], c: Cursor&) { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.status = c.token.status; } }
fn equal(s: u8[:], t: lexer::Token, kind: i64, value: u8[:]) -> bool {
    return t.kind == kind && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == value;
}
fn take(s: u8[:], c: Cursor&, kind: i64, value: u8[:]) -> bool {
    if c.status != 0 { return false; }
    if !equal(s,c.token,kind,value) { c.status = if c.token.kind == 0 { 1 } else { 2 }; return false; }
    advance(s,c); return c.status == 0;
}
fn token_kind(s: u8[:], c: Cursor&, kind: i64) -> bool {
    if c.status != 0 { return false; }
    if c.token.kind != kind { c.status = if c.token.kind == 0 { 1 } else { 2 }; return false; }
    advance(s,c); return c.status == 0;
}
fn number(s: u8[:], t: lexer::Token) -> u32, bool {
    if t.kind != 2 || t.start < 0 || t.end <= t.start || t.end > s.len { return 0,false; }
    var n: u64 = 0;
    for i in t.start..t.end {
        if s[i] < '0' || s[i] > '9' { return 0,false; }
        let digit = (s[i] - '0') as u64;
        if n > (4294967295 - digit) / 10 { return 0,false; }
        n = n * 10 + digit;
    }
    return n as u32,true;
}
struct Atom { start: i64 = 0, end: i64 = 0, kind: i64 = 0 }
fn atom(s: u8[:], c: Cursor&, parameter: lexer::Token) -> Atom {
    let first = c.token;
    // Normal parsing supplies a lexer token, but this helper is callable on
    // its own: reject forged parameter spans before either source slice.
    if parameter.kind != 1 || parameter.start < 0 || parameter.end <= parameter.start || parameter.end > s.len {
        c.status = 1; return Atom {};
    }
    if first.kind == 1 && first.start >= 0 && first.end > first.start && first.end <= s.len {
        if s[first.start..first.end] != s[parameter.start..parameter.end] { c.status = 3; return Atom {}; }
        advance(s,c); return Atom { start: first.start, end: first.end, kind: 1 };
    }
    if equal(s,first,5,"#") {
        advance(s,c);
        let last = c.token;
        if last.start != first.end { c.status = 1; return Atom {}; }
        var kind: i64 = 0;
        if equal(s,last,1,"True") { kind = 2; }
        else if equal(s,last,1,"False") { kind = 3; }
        else { c.status = 2; return Atom {}; }
        advance(s,c); return Atom { start: first.start, end: last.end, kind: kind };
    }
    c.status = if first.kind == 0 { 1 } else { 2 }; return Atom {};
}
fn fail(c: Cursor&) -> control_core::Result {
    return control_core::Result { status: if c.status == 0 { 1 } else { c.status }, start: c.token.start, end: c.token.end };
}
fn parse(s: u8[:]) -> control_core::Result {
    var c = Cursor { state: lexer::init(s) };
    advance(s,c);
    while c.status == 0 && c.token.kind == 6 { advance(s,c); }
    if !take(s,c,1,"let") { return fail(c); }
    let name = c.token;
    if name.kind != 1 || name.start < 0 || name.end > s.len || !validate::name_valid(s[name.start..name.end]) { c.status = 1; return fail(c); }
    advance(s,c);
    if !take(s,c,5,":") || !take(s,c,1,"Bool") || !take(s,c,5,"->") || !take(s,c,1,"U32") ||
       !take(s,c,5,"=") { return fail(c); }
    let function = c.token;
    if !take(s,c,1,"fn") { return fail(c); }
    let parameter = c.token;
    if parameter.kind != 1 || parameter.start < 0 || parameter.end > s.len || !validate::name_valid(s[parameter.start..parameter.end]) { c.status = 1; return fail(c); }
    advance(s,c);
    if !take(s,c,5,"=>") || !take(s,c,1,"do") || !take(s,c,5,":") ||
       !token_kind(s,c,6) || !token_kind(s,c,7) { return fail(c); }
    let if_token = c.token;
    if !take(s,c,1,"if") { return fail(c); }
    let left = atom(s,c,parameter);
    if c.status != 0 { return fail(c); }
    var p = control_core::Program { name_start: name.start, name_end: name.end,
        param_start: parameter.start, param_end: parameter.end,
        function_start: function.start, function_end: function.end,
        if_start: if_token.start, if_end: if_token.end,
        left_start: left.start, left_end: left.end, left_kind: left.kind };
    if equal(s,c.token,5,"&&") || equal(s,c.token,5,"||") {
        p.op = if equal(s,c.token,5,"&&") { 1 } else { 2 };
        p.op_start = c.token.start; p.op_end = c.token.end; advance(s,c);
        let right = atom(s,c,parameter);
        if c.status != 0 { return fail(c); }
        p.right_start = right.start; p.right_end = right.end; p.right_kind = right.kind;
    }
    if !take(s,c,5,":") || !token_kind(s,c,6) || !token_kind(s,c,7) { return fail(c); }
    if !equal(s,c.token,1,"return") {
        if c.token.kind == 1 || c.token.kind == 2 || c.token.kind == 8 { c.status = 4; }
        return fail(c);
    }
    let yes_return = c.token;
    advance(s,c); let yes = c.token; let yes_value, yes_ok = number(s,yes);
    if !yes_ok { c.status = 1; return fail(c); }
    p.yes_return_start = yes_return.start; p.yes_return_end = yes_return.end; p.yes_target = 1;
    p.yes_start = yes.start; p.yes_end = yes.end; p.yes = yes_value; advance(s,c);
    if c.token.kind == 6 { advance(s,c); }
    if !token_kind(s,c,8) { return fail(c); }
    if !equal(s,c.token,1,"else") {
        // A direct fallthrough is missing completion. Further statements may
        // complete it but are outside this prototype, so do not diagnose a
        // valid `if ...; return ...` as an established missing-return error.
        c.status = if c.token.kind == 0 || c.token.kind == 8 { 4 } else { 2 };
        return fail(c);
    }
    advance(s,c);
    if !take(s,c,5,":") || !token_kind(s,c,6) || !token_kind(s,c,7) { return fail(c); }
    if !equal(s,c.token,1,"return") {
        if c.token.kind == 1 || c.token.kind == 2 || c.token.kind == 8 { c.status = 4; }
        return fail(c);
    }
    let no_return = c.token;
    advance(s,c); let no = c.token; let no_value, no_ok = number(s,no);
    if !no_ok { c.status = 1; return fail(c); }
    p.no_return_start = no_return.start; p.no_return_end = no_return.end; p.no_target = 1;
    p.no_start = no.start; p.no_end = no.end; p.no = no_value; advance(s,c);
    if c.token.kind == 6 { advance(s,c); }
    if !token_kind(s,c,8) || !token_kind(s,c,8) { return fail(c); }
    while c.status == 0 && c.token.kind == 6 { advance(s,c); }
    if c.status != 0 || c.token.kind != 0 { return fail(c); }
    if !control_core::shape(p,s.len) { c.status = 1; return fail(c); }
    return control_core::Result { program: p };
}
