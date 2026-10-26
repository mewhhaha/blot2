// Candidate producer for a narrow private closure source fixture. No syntax or
// type authority is conveyed until closure_validate independently rechecks it.
namespace closure_parse;
import lexer;
import frontend;
import closure_core;
struct Cursor { state: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(s: u8[:], c: Cursor&) { c.token = lexer::next(s,c.state); if c.token.kind == 9 { c.bad = true; } }
fn take(s: u8[:], c: Cursor&, kind: i64, text: u8[:]) -> lexer::Token {
    let t = c.token;
    if c.bad || t.kind != kind || t.start < 0 || t.end < t.start || t.end > s.len ||
       (text.len > 0 && s[t.start..t.end] != text) { c.bad = true; return t; }
    next(s,c); return t;
}
fn name(s: u8[:], c: Cursor&) -> closure_core::Span {
    let t = take(s,c,1,"");
    if t.start < 0 || t.end <= t.start || t.end > s.len || frontend::reserved(s[t.start..t.end]) { c.bad = true; return closure_core::Span {}; }
    return closure_core::Span { start: t.start, end: t.end };
}
fn text_equal(s: u8[:], a: closure_core::Span, b: closure_core::Span) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len && s[a.start..a.end] == s[b.start..b.end];
}
// Private syntax: let F: (U32,U32)->U32 = fn (capture,arg) => do:
//   let closure = fn parameter => return parameter & capture
//   return closure(arg)
// Status 0 candidate, 1 unsupported/invalid, 2 private input size limit.
fn parse(s: u8[:]) -> closure_core::Core, i64 {
    if s.len > 4096 { return closure_core::Core {}, 2; }
    var c = Cursor { state: lexer::init(s) }; next(s,c);
    take(s,c,1,"let"); let function = name(s,c);
    take(s,c,5,":"); take(s,c,5,"("); take(s,c,1,"U32"); take(s,c,5,",");
    take(s,c,1,"U32"); take(s,c,5,")"); take(s,c,5,"->"); take(s,c,1,"U32");
    take(s,c,5,"="); take(s,c,1,"fn"); take(s,c,5,"("); let capture = name(s,c);
    take(s,c,5,","); let argument = name(s,c); take(s,c,5,")"); take(s,c,5,"=>");
    take(s,c,1,"do"); take(s,c,5,":"); take(s,c,6,""); take(s,c,7,"");
    take(s,c,1,"let"); let binding = name(s,c); take(s,c,5,"="); take(s,c,1,"fn");
    let parameter = name(s,c); take(s,c,5,"=>"); take(s,c,1,"return"); let inner_use = name(s,c);
    take(s,c,5,"&"); let capture_use = name(s,c); take(s,c,6,""); take(s,c,1,"return");
    let binding_use = name(s,c); take(s,c,5,"("); let argument_use = name(s,c); take(s,c,5,")");
    if c.token.kind == 6 { take(s,c,6,""); }
    take(s,c,8,""); take(s,c,0,"");
    if c.bad || !text_equal(s,parameter,inner_use) || !text_equal(s,capture,capture_use) ||
       !text_equal(s,binding,binding_use) || !text_equal(s,argument,argument_use) { return closure_core::Core {}, 1; }
    let names = [function,capture,argument,binding,parameter];
    for i in names.len { for j in i { if text_equal(s,names[i],names[j]) { return closure_core::Core {}, 1; } } }
    return closure_core::Core { source: s, function: function, capture: capture, argument: argument,
        binding: binding, parameter: parameter, inner_use: inner_use, capture_use: capture_use,
        binding_use: binding_use, argument_use: argument_use, schema: 1, capture_kind: 1,
        capture_version: 1, argument_version: 2, inner_version: 3, mode: 1, placement: 1,
        env_size: 4, env_align: 4, worker_depth: 1, caller_depth: 2, caller_frame: 4 }, 0;
}
