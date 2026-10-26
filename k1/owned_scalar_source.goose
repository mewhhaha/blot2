// Narrow owned expression fixture. The surrounding declared alias is assumed
// to be `type ScalarPayload[r: Region] = U32`; no general alias/type checker is
// implemented. Only fixed r/free binders and a literal seal or #Cancelled abort
// are recognized. This is not a completed CheckedFunction or public admission.
namespace owned_scalar_source;
import lexer;
struct Core { work_bytes: u32 = 0, terminal: u32 = 0, value: u32 = 0 }
struct Result { status: i64 = 1, core: Core = Core {} }
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, failed: bool = false, previous: i64 = 0 }
struct Expected { kind: i64 = 0, spelling: u8[] = [], joined: bool = false }
fn advance(source: u8[:], c: Cursor&) { c.token = lexer::next(source, c.state); if c.token.kind == 9 { c.failed = true; } }
fn exact(source: u8[:], c: Cursor&, kind: i64, spelling: u8[:], joined: bool) -> bool {
    let t = c.token;
    if c.failed || t.kind != kind || t.start < 0 || t.end <= t.start || t.end > source.len ||
       (joined && c.previous != t.start) || source[t.start..t.end] != spelling { c.failed = true; return false; }
    c.previous = t.end; advance(source, c); return !c.failed;
}
fn token_kind(source: u8[:], c: Cursor&, kind: i64) -> bool {
    if c.failed || c.token.kind != kind { c.failed = true; return false; }
    c.previous = c.token.end; advance(source, c); return !c.failed;
}
fn number(source: u8[:], c: Cursor&) -> u32 {
    let t = c.token;
    if c.failed || t.kind != 2 || t.start < 0 || t.end <= t.start || t.end > source.len { c.failed = true; return 0; }
    var n: u64 = 0;
    for p in t.start..t.end {
        let digit = source[p] as u64 - 48;
        if digit > 9 || n > (4294967295 - digit) / 10 { c.failed = true; return 0; }
        n = n * 10 + digit;
    }
    c.previous = t.end; advance(source, c); return n as u32;
}
fn parse(source: u8[:]) -> Result {
    var c = Cursor { state: lexer::init(source) }; advance(source, c);
    let head: Expected[] = [
        Expected { kind: 1, spelling: "owned" }, Expected { kind: 5, spelling: "@" },
        Expected { kind: 5, spelling: "[" }, Expected { kind: 1, spelling: "ScalarPayload" },
        Expected { kind: 5, spelling: "[" }, Expected { kind: 1, spelling: "_" }, Expected { kind: 5, spelling: "]" },
        Expected { kind: 5, spelling: "," }, Expected { kind: 5, spelling: "#" },
        Expected { kind: 1, spelling: "Cancelled", joined: true }, Expected { kind: 5, spelling: "]" }, Expected { kind: 5, spelling: "(" }
    ];
    for e in head { if !exact(source, c, e.kind, e.spelling, e.joined) { return Result {}; } }
    let work = number(source, c);
    let middle: Expected[] = [Expected { kind: 5, spelling: ")" }, Expected { kind: 1, spelling: "as" },
        Expected { kind: 1, spelling: "r" }, Expected { kind: 1, spelling: "free" },
        Expected { kind: 1, spelling: "in" }, Expected { kind: 1, spelling: "do" }, Expected { kind: 5, spelling: ":" }];
    for e in middle { if !exact(source, c, e.kind, e.spelling, false) { return Result {}; } }
    if !token_kind(source,c,6) || !token_kind(source,c,7) { return Result {}; }
    var core = Core { work_bytes: work };
    if c.token.kind == 1 && source[c.token.start..c.token.end] == "seal" {
        if !exact(source,c,1,"seal",false) || !exact(source,c,5,"(",false) ||
           !exact(source,c,1,"free",false) || !exact(source,c,5,",",false) { return Result {}; }
        core.terminal = 1; core.value = number(source,c);
    } else if c.token.kind == 1 && source[c.token.start..c.token.end] == "abort" {
        if !exact(source,c,1,"abort",false) || !exact(source,c,5,"(",false) ||
           !exact(source,c,1,"free",false) || !exact(source,c,5,",",false) ||
           !exact(source,c,5,"#",false) || !exact(source,c,1,"Cancelled",true) { return Result {}; }
        core.terminal = 2;
    } else { return Result {}; }
    if c.failed || !exact(source,c,5,")",false) { return Result {}; }
    if c.token.kind == 6 { if !token_kind(source,c,6) { return Result {}; } }
    if !token_kind(source,c,8) || c.failed || c.token.kind != 0 { return Result {}; }
    return Result { status: 0, core: core };
}
