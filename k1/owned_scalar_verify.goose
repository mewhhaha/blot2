// Independently re-recognize the entire narrow owned source against Core.
// The lexer is shared, but no parser result or numeric field is trusted.
namespace owned_scalar_verify;
import lexer;
import owned_scalar_source;
struct Reader { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, last: i64 = 0, bad: bool = false }
fn next(s: u8[:], r: Reader&) { r.t = lexer::next(s, r.lex); if r.t.kind == 9 { r.bad = true; } }
fn take(s: u8[:], r: Reader&, k: i64, spelling: u8[:], join: bool) -> bool {
    let t = r.t;
    if r.bad || t.kind != k || t.start < 0 || t.end <= t.start || t.end > s.len ||
       (join && t.start != r.last) || s[t.start..t.end] != spelling { r.bad = true; return false; }
    r.last = t.end; next(s,r); return !r.bad;
}
fn decimal(s: u8[:], r: Reader&, expected: u32) -> bool {
    let t = r.t;
    if r.bad || t.kind != 2 || t.start < 0 || t.end <= t.start || t.end > s.len { return false; }
    var n: u64 = 0;
    for i in t.start..t.end {
        let ch = s[i]; if ch < '0' || ch > '9' { return false; }
        let d = (ch - '0') as u64; if n > (4294967295 - d) / 10 { return false; }
        n = n * 10 + d;
    }
    if n != expected { return false; }
    r.last = t.end; next(s,r); return !r.bad;
}
fn matching_kind(s: u8[:], r: Reader&, k: i64) -> bool {
    if r.bad || r.t.kind != k { return false; }
    r.last = r.t.end; next(s,r); return !r.bad;
}
fn verify(s: u8[:], core: owned_scalar_source::Core) -> bool {
    if core.terminal != 1 && core.terminal != 2 { return false; }
    if core.terminal == 2 && core.value != 0 { return false; }
    var r = Reader { lex: lexer::init(s) }; next(s,r);
    if !take(s,r,1,"owned",false) || !take(s,r,5,"@",false) || !take(s,r,5,"[",false) ||
       !take(s,r,1,"ScalarPayload",false) || !take(s,r,5,"[",false) || !take(s,r,1,"_",false) ||
       !take(s,r,5,"]",false) || !take(s,r,5,",",false) || !take(s,r,5,"#",false) ||
       !take(s,r,1,"Cancelled",true) || !take(s,r,5,"]",false) || !take(s,r,5,"(",false) ||
       !decimal(s,r,core.work_bytes) || !take(s,r,5,")",false) || !take(s,r,1,"as",false) ||
       !take(s,r,1,"r",false) || !take(s,r,1,"free",false) || !take(s,r,1,"in",false) ||
       !take(s,r,1,"do",false) || !take(s,r,5,":",false) || !matching_kind(s,r,6) || !matching_kind(s,r,7) { return false; }
    if core.terminal == 1 {
        if !take(s,r,1,"seal",false) || !take(s,r,5,"(",false) || !take(s,r,1,"free",false) ||
           !take(s,r,5,",",false) || !decimal(s,r,core.value) { return false; }
    } else {
        if !take(s,r,1,"abort",false) || !take(s,r,5,"(",false) || !take(s,r,1,"free",false) ||
           !take(s,r,5,",",false) || !take(s,r,5,"#",false) || !take(s,r,1,"Cancelled",true) { return false; }
    }
    if !take(s,r,5,")",false) { return false; }
    if r.t.kind == 6 && !matching_kind(s,r,6) { return false; }
    return matching_kind(s,r,8) && !r.bad && r.t.kind == 0;
}
