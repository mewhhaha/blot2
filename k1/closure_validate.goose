// Independent source-to-Core checker for the fixed local Many closure subset.
// It independently lexes the authoritative source; no parser success flag,
// mutable handle, byte hash or caller-supplied type label grants admission.
// This is a private fixture, not a general K1 closure/artifact validator.
namespace closure_validate;
import lexer;
import frontend;
import closure_core;
import closure_resources;
fn token(s: u8[:], ts: lexer::Token[:], n: i64, kind: i64, text: u8[:]) -> bool {
    if n < 0 || n >= ts.len { return false; }
    let t = ts[n];
    return t.kind == kind && t.start >= 0 && t.end >= t.start && t.end <= s.len &&
        (text.len == 0 || s[t.start..t.end] == text);
}
fn name(s: u8[:], ts: lexer::Token[:], n: i64, span: closure_core::Span) -> bool {
    if !token(s,ts,n,1,"") { return false; }
    let t = ts[n];
    return t.end > t.start && span.start == t.start && span.end == t.end && !frontend::reserved(s[t.start..t.end]);
}
fn eq(s: u8[:], a: closure_core::Span, b: closure_core::Span) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len &&
        s[a.start..a.end] == s[b.start..b.end];
}
fn verify(source: u8[:], core: closure_core::Core&) -> bool {
    if source.len > 4096 || core.source[..] != source { return false; }
    // The private contract contains one U32 capture and one indirect call.
    // Values are recomputed from the source shape and fixed layout; resource
    // fields are exact for this producer, not accepted as free assertions.
    if core.schema != 1 || core.capture_kind != 1 || core.capture_version != 1 ||
       core.argument_version != 2 || core.inner_version != 3 || core.mode != 1 ||
       core.placement != 1 || core.escaping != 0 || core.env_size != 4 ||
       core.env_align != 4 || core.env_offset != 0 || core.code_slot != 0 ||
       core.worker_depth != 1 || core.worker_frame != 0 || core.caller_depth != 2 || core.caller_frame != 4 { return false; }
    let functions = [closure_resources::Fn { own: 0, frame: core.worker_frame, depth: core.worker_depth },
                     closure_resources::Fn { own: core.env_size, frame: core.caller_frame, depth: core.caller_depth, callee: 1, indirect: true }];
    if closure_resources::validate(functions) != 0 { return false; }
    var state = lexer::init(source); var ts: lexer::Token[..64] = [];
    loop {
        let t = lexer::next(source,state);
        if t.kind == 9 || ts.len == 64 { return false; }
        ts.push(t); if t.kind == 0 { break; }
    }
    if ts.len != 41 && ts.len != 40 { return false; }
    if !token(source,ts,0,1,"let") || !name(source,ts,1,core.function) ||
       !token(source,ts,2,5,":") || !token(source,ts,3,5,"(") || !token(source,ts,4,1,"U32") ||
       !token(source,ts,5,5,",") || !token(source,ts,6,1,"U32") || !token(source,ts,7,5,")") ||
       !token(source,ts,8,5,"->") || !token(source,ts,9,1,"U32") || !token(source,ts,10,5,"=") ||
       !token(source,ts,11,1,"fn") || !token(source,ts,12,5,"(") || !name(source,ts,13,core.capture) ||
       !token(source,ts,14,5,",") || !name(source,ts,15,core.argument) || !token(source,ts,16,5,")") ||
       !token(source,ts,17,5,"=>") || !token(source,ts,18,1,"do") || !token(source,ts,19,5,":") ||
       !token(source,ts,20,6,"") || !token(source,ts,21,7,"") || !token(source,ts,22,1,"let") ||
       !name(source,ts,23,core.binding) || !token(source,ts,24,5,"=") || !token(source,ts,25,1,"fn") ||
       !name(source,ts,26,core.parameter) || !token(source,ts,27,5,"=>") || !token(source,ts,28,1,"return") ||
       !name(source,ts,29,core.inner_use) || !token(source,ts,30,5,"&") || !name(source,ts,31,core.capture_use) ||
       !token(source,ts,32,6,"") || !token(source,ts,33,1,"return") || !name(source,ts,34,core.binding_use) ||
       !token(source,ts,35,5,"(") || !name(source,ts,36,core.argument_use) || !token(source,ts,37,5,")") { return false; }
    if ts.len == 41 {
        if !token(source,ts,38,6,"") || !token(source,ts,39,8,"") || !token(source,ts,40,0,"") { return false; }
    } else if !token(source,ts,38,8,"") || !token(source,ts,39,0,"") { return false; }
    if !eq(source,core.parameter,core.inner_use) || !eq(source,core.capture,core.capture_use) ||
       !eq(source,core.binding,core.binding_use) || !eq(source,core.argument,core.argument_use) { return false; }
    let names = [core.function,core.capture,core.argument,core.binding,core.parameter];
    for i in names.len { for j in i { if eq(source,names[i],names[j]) { return false; } } }
    return true;
}
