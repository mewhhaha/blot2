// Source-bound, single-function-body Owned lifecycle subset. The surrounding
// declared alias is `type ScalarPayload[r: Region] = U32`; its declaration is
// trusted fixture context. This is not general source/type/effect admission.
namespace owned_program_source;
import lexer;
import owned_scalar_source;
struct Core { owned_start: i64 = 0, owned_end: i64 = 0, owned: owned_scalar_source::Core = owned_scalar_source::Core {}, moved: bool = false }
struct Result { status: i64 = 1, core: Core = Core {} }
struct Reader { lex: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false, last: i64 = 0 }
struct Expected { kind: i64 = 0, spelling: u8[] = [], joined: bool = false }
fn next(s: u8[:], r: Reader&) { r.token = lexer::next(s, r.lex); if r.token.kind == 9 { r.bad = true; } }
fn take(s: u8[:], r: Reader&, k: i64, text: u8[:], join: bool) -> bool {
    let t = r.token;
    if r.bad || t.kind != k || t.start < 0 || t.end <= t.start || t.end > s.len ||
       (join && t.start != r.last) || s[t.start..t.end] != text { r.bad = true; return false; }
    r.last = t.end; next(s,r); return !r.bad;
}
fn kind(s: u8[:], r: Reader&, k: i64) -> bool {
    if r.bad || r.token.kind != k { return false; }
    r.last = r.token.end; next(s,r); return !r.bad;
}
fn group(s: u8[:], r: Reader&, expected: Expected[:]) -> bool {
    for e in expected { if !take(s,r,e.kind,e.spelling,e.joined) { return false; } } return true;
}
fn parse(s: u8[:]) -> Result {
    var r = Reader { lex: lexer::init(s) }; next(s,r);
    let first: Expected[] = [Expected {kind: 1, spelling:"let"}, Expected {kind: 1, spelling:"built"}, Expected {kind:5, spelling:"="}];
    if !group(s,r,first) || r.token.kind != 1 || s[r.token.start..r.token.end] != "owned" { return Result {}; }
    let start = r.token.start;
    // The owned expression's first DEDENT ends its one-statement body. Its
    // independent parser validates the whole extracted expression afterwards.
    while !r.bad && r.token.kind != 8 && r.token.kind != 0 { next(s,r); }
    if r.bad || r.token.kind != 8 || r.token.start < start || r.token.start > s.len { return Result {}; }
    let end = r.token.start;
    let built = owned_scalar_source::parse(s[start..end]);
    if built.status != 0 || !kind(s,r,8) { return Result {}; }
    let case_prefix: Expected[] = [
        Expected {kind:1,spelling:"case"}, Expected {kind:1,spelling:"built"}, Expected {kind:5,spelling:":"}];
    if !group(s,r,case_prefix) || !kind(s,r,6) || !kind(s,r,7) { return Result {}; }
    let err: Expected[] = [Expected {kind:5,spelling:"#"}, Expected {kind:1,spelling:"Err",joined:true},
        Expected {kind:5,spelling:"("}, Expected {kind:1,spelling:"e"}, Expected {kind:5,spelling:")"},
        Expected {kind:5,spelling:"=>"}, Expected {kind:1,spelling:"return"}, Expected {kind:5,spelling:"#"},
        Expected {kind:1,spelling:"Err",joined:true}, Expected {kind:5,spelling:"("}, Expected {kind:1,spelling:"e"}, Expected {kind:5,spelling:")"}];
    if !group(s,r,err) || !kind(s,r,6) { return Result {}; }
    let ok: Expected[] = [Expected {kind:5,spelling:"#"}, Expected {kind:1,spelling:"Ok",joined:true},
        Expected {kind:5,spelling:"("}, Expected {kind:1,spelling:"h"}, Expected {kind:5,spelling:")"},
        Expected {kind:5,spelling:"=>"}, Expected {kind:1,spelling:"do"}, Expected {kind:5,spelling:":"}];
    if !group(s,r,ok) || !kind(s,r,6) || !kind(s,r,7) || !take(s,r,1,"let",false) { return Result {}; }
    var core = Core { owned_start:start, owned_end:end, owned:built.core };
    if r.token.kind == 1 && s[r.token.start..r.token.end] == "m" {
        let move: Expected[] = [Expected {kind:1,spelling:"m"}, Expected {kind:5,spelling:"="}, Expected {kind:1,spelling:"h"}];
        if !group(s,r,move) || !kind(s,r,6) || !take(s,r,1,"let",false) { return Result {}; }
        core.moved = true;
    }
    let bind: Expected[] = [Expected {kind:1,spelling:"value"}, Expected {kind:5,spelling:"="},
        Expected {kind:1,spelling:"owned"}, Expected {kind:5,spelling:"."}, Expected {kind:1,spelling:"open"}, Expected {kind:5,spelling:"("}];
    if !group(s,r,bind) || !take(s,r,1,if core.moved {"m"} else {"h"},false) { return Result {}; }
    let open: Expected[] = [Expected {kind:5,spelling:")"}, Expected {kind:1,spelling:"as"}, Expected {kind:1,spelling:"s"},
        Expected {kind:1,spelling:"payload"}, Expected {kind:1,spelling:"in"}, Expected {kind:1,spelling:"do"}, Expected {kind:5,spelling:":"}];
    if !group(s,r,open) || !kind(s,r,6) || !kind(s,r,7) || !take(s,r,1,"break",false) || !take(s,r,1,"payload",false) ||
       !kind(s,r,6) || !kind(s,r,8) { return Result {}; }
    let close: Expected[] = [Expected {kind:1,spelling:"owned"}, Expected {kind:5,spelling:"."}, Expected {kind:1,spelling:"close"}, Expected {kind:5,spelling:"("}];
    if !group(s,r,close) || !take(s,r,1,if core.moved {"m"} else {"h"},false) || !take(s,r,5,")",false) || !kind(s,r,6) { return Result {}; }
    let ret: Expected[] = [Expected {kind:1,spelling:"return"}, Expected {kind:5,spelling:"#"}, Expected {kind:1,spelling:"Ok",joined:true},
        Expected {kind:5,spelling:"("}, Expected {kind:1,spelling:"value"}, Expected {kind:5,spelling:")"}];
    if !group(s,r,ret) { return Result {}; }
    if r.token.kind == 6 && !kind(s,r,6) { return Result {}; }
    if !kind(s,r,8) || !kind(s,r,8) || r.bad || r.token.kind != 0 { return Result {}; }
    return Result { status:0, core:core };
}
