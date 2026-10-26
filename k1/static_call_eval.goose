// Closed pure scalar direct-call fixture. One required-static U32 literal call
// follows a module of U32 -> U32 noncapturing pure functions accepted by the
// existing independently verified scalar module frontend. No foreign calls,
// captures, runtime identities, arbitrary nesting, products or arrays are
// accepted here. This local meter is not complete C09 accounting.
namespace static_call_eval;
import lexer;
import validate;
import module_frontend;
import module_core;
import static_parse;
import static_budget;
struct Result {status:i64=1,bits:u32=0,steps:u32=0,bytes:u32=0,depth:u32=0}
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn advance(s:u8[:],c:Cursor&) {c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.bad=true;}}
fn is(s:u8[:],t:lexer::Token,k:i64,v:u8[:])->bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn take(s:u8[:],c:Cursor&,k:i64,v:u8[:])->bool {if c.bad || !is(s,c.t,k,v){c.bad=true;return false;}advance(s,c);return !c.bad;}
fn evaluate(s:u8[:])->Result {
    var scan=Cursor {lex:lexer::init(s)};advance(s,scan);
    while !scan.bad && scan.t.kind!=0 && !is(s,scan.t,1,"static") {advance(s,scan);}
    if scan.bad || scan.t.kind==0 || scan.t.start<=0 {return Result {};}
    let split=scan.t.start;var mod,status=module_frontend::parse(s[..split]);if status!=0 {return Result {};}
    var core=module_frontend::to_core(mod);if module_frontend::verify_core(mod,core)!=0 {return Result {};}
    let tail=s[split..];var c=Cursor {lex:lexer::init(tail)};advance(tail,c);
    if !take(tail,c,1,"static") || !take(tail,c,1,"let"){return Result {};}
    let name=c.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>tail.len || !validate::name_valid(tail[name.start..name.end]) {return Result {};}
    advance(tail,c);if !take(tail,c,5,":") || !take(tail,c,1,"U32") || !take(tail,c,5,"="){return Result {};}
    let callee=c.t;if callee.kind!=1 || callee.start<0 || callee.end<=callee.start || callee.end>tail.len || !validate::name_valid(tail[callee.start..callee.end]) {return Result {};}
    var index:i64=-1;
    for f,i in core.functions {
        if tail[name.start..name.end]==core.source[f.name_start..f.name_end] {return Result {};}
        if tail[callee.start..callee.end]==core.source[f.name_start..f.name_end] {index=i;}
    }
    if index<0 {return Result {};}
    advance(tail,c);if !take(tail,c,5,"("){return Result {};}
    let lit=c.t;if lit.kind!=2{return Result {};}
    let initial,ok=static_parse::integer(tail,lit);if !ok{return Result {};}
    advance(tail,c);if !take(tail,c,5,")"){return Result {};}
    while !c.bad && c.t.kind==6 {advance(tail,c);}if c.bad || c.t.kind!=0 {return Result {};}
    var budget=static_budget::Budget {};if !static_budget::step(budget){return Result {status:2};}
    var value=initial;var depth:u32=0;var current=index;
    loop {
        if current<0 || current>=core.functions.len {return Result {};}
        if depth>=128 {return Result {status:2,steps:budget.steps,depth:depth};}depth+=1;
        // Charge one call and one result expression, with literal operands
        // separately charged. This fixed fixture defines no general schedule.
        if !static_budget::step(budget) || !static_budget::step(budget){return Result {status:2,steps:budget.steps,depth:depth};}
        let f=core.functions[current];let result=f.values[f.result_id];
        if result.producer==1 {break;}
        if result.producer==2 {if !static_budget::step(budget){return Result {status:2,steps:budget.steps,depth:depth};}value=result.literal;break;}
        let left=f.values[result.left_id];var a=value;
        if left.producer==2 {if !static_budget::step(budget){return Result {status:2,steps:budget.steps,depth:depth};}a=left.literal;}
        if result.producer==3 {
            let right=f.values[result.right_id];var b=value;
            if right.producer==2 {if !static_budget::step(budget){return Result {status:2,steps:budget.steps,depth:depth};}b=right.literal;}
            value=a&b;break;
        }
        if result.producer!=4 {return Result {};}
        value=a;current=result.callee_id;
    }
    if !static_budget::produce(budget,4) {return Result {status:2,steps:budget.steps,depth:depth};}
    return Result {status:0,bits:value,steps:budget.steps,bytes:budget.bytes,depth:depth};
}
