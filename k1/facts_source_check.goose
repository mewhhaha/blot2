// Independent lexer/source binding verifier for the two nested U32 guards.
// Candidate IDs and source names become usable only after this recheck; this
// is not complete K1 parsing, source resolution, or portable provenance.
namespace facts_source_check;
import lexer;
import frontend;
import work;
import facts_source;
struct Check { status: u32 = 0, receipt: work::Receipt = work::Receipt {} }
fn failure(r: work::Receipt) -> Check { return Check { status: if r.status == 1 { 3 } else if r.status == 2 { 2 } else { 4 }, receipt: r }; }
fn token(s: u8[:], ts: lexer::Token[:], n: i64, kind: i64, text: u8[:]) -> bool {
    if n < 0 || n >= ts.len { return false; }
    let t = ts[n]; return t.kind == kind && t.start >= 0 && t.end >= t.start && t.end <= s.len && (text.len == 0 || s[t.start..t.end] == text);
}
fn named(s: u8[:], ts: lexer::Token[:], n: i64, p: facts_source::Span) -> bool {
    if !token(s,ts,n,1,"") { return false; }
    let t=ts[n]; return t.end > t.start && t.start == p.start && t.end == p.end && !frontend::reserved(s[t.start..t.end]);
}
fn same(s: u8[:], a: facts_source::Span, b: facts_source::Span) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len && s[a.start..a.end] == s[b.start..b.end];
}
fn name_id(s: u8[:], ts: lexer::Token[:], n: i64, names: facts_source::Span[3]) -> u32 {
    if !token(s,ts,n,1,"") { return 0; }
    let t=ts[n]; let p=facts_source::Span { start:t.start, end:t.end };
    for i in 3 { if same(s,p,names[i]) { return (i + 1) as u32; } }
    return 0;
}
fn verify(source: u8[:], p: facts_source::Program&, meter: work::Meter&, phase: u32) -> Check {
    if phase < 4 || phase > 7 { return Check { status: 4 }; }
    if source.len > 4096 || p.source[..] != source { return Check { status: 1 }; }
    var state=lexer::init(source); var ts: lexer::Token[..80] = [];
    loop {
        let r=work::charge(meter,phase,1); if r.status != 0 { return failure(r); }
        let t=lexer::next(source,state); if t.kind==9 || ts.len==80 { return Check { status: 1 }; }
        ts.push(t); if t.kind==0 { break; }
    }
    if ts.len != 65 && ts.len != 66 { return Check { status: 1 }; }
    if !token(source,ts,0,1,"let") || !named(source,ts,1,p.function) || !token(source,ts,2,5,":") ||
       !token(source,ts,3,5,"(") || !token(source,ts,4,1,"U32") || !token(source,ts,5,5,",") ||
       !token(source,ts,6,1,"U32") || !token(source,ts,7,5,",") || !token(source,ts,8,1,"U32") ||
       !token(source,ts,9,5,")") || !token(source,ts,10,5,"->") || !token(source,ts,11,1,"U32") ||
       !token(source,ts,12,5,"=") || !token(source,ts,13,1,"fn") || !token(source,ts,14,5,"(") ||
       !named(source,ts,15,p.names[0]) || !token(source,ts,16,5,",") || !named(source,ts,17,p.names[1]) ||
       !token(source,ts,18,5,",") || !named(source,ts,19,p.names[2]) || !token(source,ts,20,5,")") ||
       !token(source,ts,21,5,"=>") || !token(source,ts,22,1,"do") || !token(source,ts,23,5,":") ||
       !token(source,ts,24,6,"") || !token(source,ts,25,7,"") || !token(source,ts,26,1,"if") ||
       !token(source,ts,30,5,":") || !token(source,ts,31,6,"") || !token(source,ts,32,7,"") ||
       !token(source,ts,33,1,"if") || !token(source,ts,37,5,":") || !token(source,ts,38,6,"") ||
       !token(source,ts,39,7,"") || !token(source,ts,40,5,"(") || !token(source,ts,41,5,")") ||
       !token(source,ts,42,6,"") || !token(source,ts,43,8,"") || !token(source,ts,44,1,"else") ||
       !token(source,ts,45,5,":") || !token(source,ts,46,6,"") || !token(source,ts,47,7,"") ||
       !token(source,ts,48,5,"(") || !token(source,ts,49,5,")") || !token(source,ts,50,6,"") ||
       !token(source,ts,51,8,"") || !token(source,ts,52,1,"return") || name_id(source,ts,53,p.names) != 1 ||
       !token(source,ts,54,6,"") || !token(source,ts,55,8,"") || !token(source,ts,56,1,"else") ||
       !token(source,ts,57,5,":") || !token(source,ts,58,6,"") || !token(source,ts,59,7,"") ||
       !token(source,ts,60,1,"return") || name_id(source,ts,61,p.names) != 3 { return Check { status: 1 }; }
    if ts.len == 66 {
        if !token(source,ts,62,6,"") || !token(source,ts,63,8,"") || !token(source,ts,64,8,"") || !token(source,ts,65,0,"") { return Check { status: 1 }; }
    } else if !token(source,ts,62,8,"") || !token(source,ts,63,8,"") || !token(source,ts,64,0,"") { return Check { status: 1 }; }
    for i in 3 { if same(source,p.function,p.names[i]) { return Check { status: 1 }; } for j in i { if same(source,p.names[i],p.names[j]) { return Check { status: 1 }; } } }
    for g in 2 {
        let left = if g == 0 { 27 } else { 34 }; let op = left + 1; let right = left + 2;
        let l = name_id(source,ts,left,p.names); let r = name_id(source,ts,right,p.names);
        let lt = token(source,ts,op,5,"<"); let le = token(source,ts,op,5,"<=");
        if l == 0 || r == 0 || l == r || (!lt && !le) || p.guards[g].left != l || p.guards[g].right != r || p.guards[g].strict != lt { return Check { status: 1 }; }
    }
    return Check {};
}
