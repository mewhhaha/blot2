// One source entry for existing unified scalar or bounded iteration candidates.
// Public K1 check/build remain unavailable; statuses are private fixture codes.
namespace compiler_frontend;
import lexer;
import validate;
import unified_frontend;
import iteration_parse;
import compiler_core;
import compiler_validate;
import mixed_frontend;
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
// Preserve the scalar fixture's exposed unbound/arithmetic categories. The
// iteration parser's status 5 instead means a bad control target and must not
// be mapped to an arithmetic diagnostic.
fn rejected(scalar:i64,iteration:i64) -> i64 {
    if scalar==3 || scalar==5 {return scalar;}
    if iteration==2 || iteration==3 {return iteration;}
    return 1;
}
fn advance(s:u8[:],c:Cursor&) {if !c.bad {c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.bad=true;}}}
fn take(s:u8[:],c:Cursor&,kind:i64,value:u8[:]) -> bool {
    let t=c.t;if c.bad || t.kind!=kind || t.start<0 || t.end<=t.start || t.end>s.len || s[t.start..t.end]!=value {c.bad=true;return false;}
    advance(s,c);return !c.bad;
}
fn legacy_parse(source:u8[:]) -> compiler_core::Result {
    if source.len>16777216 {return compiler_core::Result {status:2};}
    var scalar=unified_frontend::parse(source);
    if scalar.status==0 {
        var p=compiler_core::Program {source:source,variant:1,scalar:copy(scalar.program)};
        if !compiler_validate::verify(source,p) {return compiler_core::Result {status:1};}
        return compiler_core::Result {program:p};
    }
    // The separate loop parser has a smaller private bound; scalar programs
    // retain the existing unified frontend's complete source-size allowance.
    if source.len>65536 {return compiler_core::Result {status:rejected(scalar.status,2)};}
    var c=Cursor {lex:lexer::init(source)};advance(source,c);while !c.bad && c.t.kind==6 {advance(source,c);}
    if !take(source,c,1,"let") {return compiler_core::Result {status:rejected(scalar.status,1)};}
    let name=c.t;
    if c.bad || name.kind!=1 || name.start<0 || name.end<=name.start || name.end>source.len || !validate::name_valid(source[name.start..name.end]) {return compiler_core::Result {status:1};}
    advance(source,c);
    if !take(source,c,5,":") || !take(source,c,1,"U32") || !take(source,c,5,"->") || !take(source,c,1,"U32") || !take(source,c,5,"=") {return compiler_core::Result {status:1};}
    let first=c.t;
    if c.bad || first.kind!=1 || first.start<0 || first.end<=first.start || first.end>source.len || source[first.start..first.end]!="fn" {return compiler_core::Result {status:1};}
    let tree,status=iteration_parse::parse(source[first.start..]);
    // Unified status 5 specifically denotes unproved arithmetic; iteration's
    // status 5 means a bad control target, so never report it as arithmetic.
    if status!=0 {return compiler_core::Result {status:rejected(scalar.status,status)};}
    var p=compiler_core::Program {source:source,variant:2,name_start:name.start,name_end:name.end,fn_start:first.start,body:copy(tree)};
    if !compiler_validate::verify(source,p) {return compiler_core::Result {status:1};}
    return compiler_core::Result {program:p};
}

// Preserve every previous acceptance and rejection status. A new variant is
// used only when the original paths reject and mixed checking succeeds.
fn parse(source:u8[:]) -> compiler_core::Result {
    var prior=legacy_parse(source);if prior.status==0 {return prior;}
    if source.len>65536 {return prior;}
    var candidate=mixed_frontend::parse(source);
    if candidate.status!=0 || candidate.program.variant!=2 {return prior;}
    var result=compiler_core::Program {source:source,variant:3,mixed:copy(candidate.program)};
    if !compiler_validate::verify(source,result) {return prior;}
    return compiler_core::Result {program:result};
}
