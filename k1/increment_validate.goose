// Independent lexical/source/Core/evidence check. The expected source belongs
// to the caller; self-reported source and counters do not authenticate it.
// It recognizes only one immutable U32 parameter and one guarded successor.
// This is not the complete proof engine or a portable artifact validator.
namespace increment_validate;
import lexer;
import frontend;
import work;
import increment_core;
struct Check { status: u32 = 0, receipt: work::Receipt = work::Receipt {} }
fn failure(r: work::Receipt) -> Check {
    return Check { status: if r.status == 1 { 3 } else if r.status == 2 { 2 } else { 4 }, receipt: r };
}
fn token(s: u8[:], ts: lexer::Token[:], n: i64, kind: i64, text: u8[:]) -> bool {
    if n < 0 || n >= ts.len { return false; }
    let t = ts[n];
    return t.kind == kind && t.start >= 0 && t.end >= t.start && t.end <= s.len &&
        (text.len == 0 || s[t.start..t.end] == text);
}
fn span(s: u8[:], ts: lexer::Token[:], n: i64, kind: i64, expected: increment_core::Span) -> bool {
    return token(s,ts,n,kind,"") && ts[n].start == expected.start && ts[n].end == expected.end && expected.end > expected.start;
}
fn same_name(s: u8[:], a: increment_core::Span, b: increment_core::Span) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len && s[a.start..a.end] == s[b.start..b.end];
}
fn verify(source: u8[:], core: increment_core::Core&, meter: work::Meter&, phase: u32) -> Check {
    if phase < 5 || phase > 7 { return Check { status: 4 }; }
    if source.len > 4096 || core.source[..] != source { return Check { status: 1 }; }
    let header = work::charge(meter,phase,4);
    if header.status != 0 { return failure(header); }
    if core.schema != 1 || core.parameter_version != 1 || core.result_version != 2 ||
       core.true_scope != 2 || core.false_scope != 3 { return Check { status: 1 }; }
    var state = lexer::init(source); var ts: lexer::Token[..64] = [];
    loop {
        let receipt = work::charge(meter,phase,1);
        if receipt.status != 0 { return failure(receipt); }
        let t = lexer::next(source,state);
        if t.kind == 9 || ts.len == 64 { return Check { status: 1 }; }
        ts.push(t); if t.kind == 0 { break; }
    }
    if ts.len != 36 && ts.len != 37 { return Check { status: 1 }; }
    if !token(source,ts,0,1,"let") || !span(source,ts,1,1,core.function) || !token(source,ts,2,5,":") ||
       !token(source,ts,3,1,"U32") || !token(source,ts,4,5,"->") || !token(source,ts,5,1,"U32") ||
       !token(source,ts,6,5,"=") || !token(source,ts,7,1,"fn") || !span(source,ts,8,1,core.parameter) ||
       !token(source,ts,9,5,"=>") || !token(source,ts,10,1,"do") || !token(source,ts,11,5,":") ||
       !token(source,ts,12,6,"") || !token(source,ts,13,7,"") || !token(source,ts,14,1,"if") ||
       !span(source,ts,15,1,core.guard_use) || !token(source,ts,16,5,"<") ||
       !span(source,ts,17,2,core.limit) || !token(source,ts,17,2,"4294967295") ||
       !token(source,ts,18,5,":") || !token(source,ts,19,6,"") || !token(source,ts,20,7,"") ||
       !token(source,ts,21,1,"return") || !span(source,ts,22,1,core.add_use) || !token(source,ts,23,5,"+") ||
       !span(source,ts,24,2,core.one) || !token(source,ts,24,2,"1") || !token(source,ts,25,6,"") ||
       !token(source,ts,26,8,"") || !token(source,ts,27,1,"else") || !token(source,ts,28,5,":") ||
       !token(source,ts,29,6,"") || !token(source,ts,30,7,"") || !token(source,ts,31,1,"return") ||
       !span(source,ts,32,1,core.else_use) { return Check { status: 1 }; }
    if ts.len == 37 {
        if !token(source,ts,33,6,"") || !token(source,ts,34,8,"") || !token(source,ts,35,8,"") || !token(source,ts,36,0,"") { return Check { status: 1 }; }
    } else if !token(source,ts,33,8,"") || !token(source,ts,34,8,"") || !token(source,ts,35,0,"") { return Check { status: 1 }; }
    if frontend::reserved(source[core.function.start..core.function.end]) ||
       frontend::reserved(source[core.parameter.start..core.parameter.end]) || same_name(source,core.function,core.parameter) ||
       !same_name(source,core.parameter,core.guard_use) || !same_name(source,core.parameter,core.add_use) ||
       !same_name(source,core.parameter,core.else_use) { return Check { status: 1 }; }
    for i in 3 {
        let receipt = work::charge(meter,phase,20);
        if receipt.status != 0 { return failure(receipt); }
        let expected = if i == 0 { increment_core::Term { kind: 1, value: 0, version: 1 } }
            else if i == 1 { increment_core::Term { kind: 2, literal: 4294967295 } }
            else { increment_core::Term { kind: 2, literal: 1 } };
        if !increment_core::same_term(core.terms[i],expected) { return Check { status: 1 }; }
    }
    let guard_fact = work::charge(meter,phase,20); if guard_fact.status != 0 { return failure(guard_fact); }
    if !increment_core::same_evidence(core.evidence[0], increment_core::Evidence { rule: 1, scope: 2, left: 1, right: 2 }) { return Check { status: 1 }; }
    let successor = work::charge(meter,phase,20); if successor.status != 0 { return failure(successor); }
    if core.evidence[1].rule != 2 || core.evidence[1].scope != 2 ||
       core.evidence[1].left != 1 || core.evidence[1].right != 3 ||
       core.evidence[1].result != 1 || core.evidence[1].result_version != 2 { return Check { status: 1 }; }
    // The prerequisite edge is a separate visit. Rule 2 uses the strict true
    // edge of the same immutable U32 value, so x+1 is at most MAX.
    let prior = work::charge(meter,phase,20); if prior.status != 0 { return failure(prior); }
    if core.evidence[1].prior != 1 { return Check { status: 1 }; }
    return Check {};
}
