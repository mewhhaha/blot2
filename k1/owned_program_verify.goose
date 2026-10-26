// Separately recognizes the complete body and checks every checked-Core field.
// Shares only the lexer and narrow Owned-expression verifier with producer;
// it does not call owned_program_source::parse or trust recorded source spans.
namespace owned_program_verify;
import lexer;
import owned_scalar_verify;
import owned_program_source;
struct Scan { lex: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, previous: i64 = 0, failed: bool = false }
fn next(s: u8[:], r: Scan&) { r.token = lexer::next(s,r.lex); if r.token.kind == 9 { r.failed = true; } }
fn expect(s: u8[:], r: Scan&, text: u8[:], adjacent: bool) -> bool {
    let t = r.token;
    if r.failed || t.kind == 0 || t.kind >= 6 || t.start < 0 || t.end <= t.start || t.end > s.len ||
       (adjacent && t.start != r.previous) || s[t.start..t.end] != text { return false; }
    r.previous = t.end; next(s,r); return !r.failed;
}
fn all(s: u8[:], r: Scan&, spellings: const u8[:][:]) -> bool {
    for text in spellings { if !expect(s,r,text,false) { return false; } } return true;
}
fn k(s: u8[:], r: Scan&, expected: i64) -> bool {
    if r.failed || r.token.kind != expected { return false; }
    r.previous = r.token.end; next(s,r); return !r.failed;
}
fn verify(s: u8[:], core: owned_program_source::Core) -> bool {
    var r = Scan { lex:lexer::init(s) }; next(s,r);
    if !all(s,r,["let","built","="]) || r.token.kind != 1 { return false; }
    let begin = r.token.start;
    while !r.failed && r.token.kind != 8 && r.token.kind != 0 { next(s,r); }
    if r.failed || r.token.kind != 8 || begin != core.owned_start || r.token.start != core.owned_end ||
       begin < 0 || core.owned_end < begin || core.owned_end > s.len ||
       !owned_scalar_verify::verify(s[begin..core.owned_end],core.owned) || !k(s,r,8) { return false; }
    if !all(s,r,["case","built",":"]) || !k(s,r,6) || !k(s,r,7) ||
       !expect(s,r,"#",false) || !expect(s,r,"Err",true) || !all(s,r,["(","e",")","=>","return","#"]) ||
       !expect(s,r,"Err",true) || !all(s,r,["(","e",")"]) || !k(s,r,6) ||
       !expect(s,r,"#",false) || !expect(s,r,"Ok",true) || !all(s,r,["(","h",")","=>","do",":"]) ||
       !k(s,r,6) || !k(s,r,7) || !expect(s,r,"let",false) { return false; }
    if core.moved && (!all(s,r,["m","=","h"]) || !k(s,r,6) || !expect(s,r,"let",false)) { return false; }
    if !all(s,r,["value","=","owned",".","open","("]) ||
       !expect(s,r,if core.moved {"m"} else {"h"},false) || !all(s,r,[")","as","s","payload","in","do",":"]) ||
       !k(s,r,6) || !k(s,r,7) || !all(s,r,["break","payload"]) || !k(s,r,6) || !k(s,r,8) ||
       !all(s,r,["owned",".","close","("]) || !expect(s,r,if core.moved {"m"} else {"h"},false) ||
       !expect(s,r,")",false) || !k(s,r,6) || !all(s,r,["return","#"]) || !expect(s,r,"Ok",true) ||
       !all(s,r,["(","value",")"]) { return false; }
    if r.token.kind == 6 && !k(s,r,6) { return false; }
    return k(s,r,8) && k(s,r,8) && !r.failed && r.token.kind == 0;
}
