// Producer for one fully spelled U32 copy-into declaration. Names, signature,
// effects, resource envelope and control structure are deliberately fixed;
// unsupported source is rejected. No general parser/borrow checker is implied.
namespace loop_parse;
import lexer;
import loop_core;
struct Cursor { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false }
fn next(source: u8[:], c: Cursor&) { c.t = lexer::next(source,c.lex); if c.t.kind == 9 { c.bad = true; } }
fn take(source: u8[:], c: Cursor&, kind: i64, value: u8[:]) -> loop_core::Span {
    let t = c.t;
    if c.bad || t.kind != kind || t.start < 0 || t.end <= t.start || t.end > source.len || source[t.start..t.end] != value {
        c.bad = true; return loop_core::Span {};
    }
    next(source,c); return loop_core::Span { start: t.start, end: t.end };
}
fn token(source: u8[:], c: Cursor&, kind: i64) { if c.bad || c.t.kind != kind { c.bad = true; return; } next(source,c); }
fn parse(source: u8[:], context: loop_core::Context) -> loop_core::Core, i64 {
    if source.len > 4096 { return loop_core::Core {},2; }
    if !loop_core::context_valid(context) { return loop_core::Core {},1; }
    var c = Cursor { lex: lexer::init(source) }; next(source,c);
    while !c.bad && c.t.kind == 6 { next(source,c); }
    let _ = take(source,c,1,"pub"); let _ = take(source,c,1,"let"); let _ = take(source,c,1,"copy_into"); let _ = take(source,c,5,":");
    let _ = take(source,c,1,"forall"); let _ = take(source,c,5,"[");
    for name in ["r","s"] { let _ = take(source,c,1,name); let _ = take(source,c,5,":"); let _ = take(source,c,1,"Region"); let _ = take(source,c,5,","); }
    for name in ["n","c"] { let _ = take(source,c,1,name); let _ = take(source,c,5,":"); let _ = take(source,c,1,"Nat"); let _ = take(source,c,5,","); }
    let _ = take(source,c,1,"d"); let _ = take(source,c,5,":"); let _ = take(source,c,1,"Domain");
    let _ = take(source,c,5,"]"); let _ = take(source,c,5,"=>"); let _ = take(source,c,1,"Fn"); let _ = take(source,c,5,"[");
    let _ = take(source,c,1,"static"); let _ = take(source,c,5,","); let _ = take(source,c,1,"Many"); let _ = take(source,c,5,",");
    let _ = take(source,c,5,"("); let _ = take(source,c,1,"View"); let _ = take(source,c,5,"[");
    let _ = take(source,c,1,"r"); let _ = take(source,c,5,","); let _ = take(source,c,1,"U32"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"n"); let _ = take(source,c,5,","); let _ = take(source,c,1,"d"); let _ = take(source,c,5,"]"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"Builder"); let _ = take(source,c,5,"["); let _ = take(source,c,1,"s"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"U32"); let _ = take(source,c,5,","); let _ = take(source,c,2,"0"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"c"); let _ = take(source,c,5,","); let _ = take(source,c,1,"Append"); let _ = take(source,c,5,"]"); let _ = take(source,c,5,")");
    let _ = take(source,c,5,","); let _ = take(source,c,1,"Builder"); let _ = take(source,c,5,"["); let _ = take(source,c,1,"s"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"U32"); let _ = take(source,c,5,","); let _ = take(source,c,1,"n"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"c"); let _ = take(source,c,5,","); let _ = take(source,c,1,"Append"); let _ = take(source,c,5,"]"); let _ = take(source,c,5,"]");
    let _ = take(source,c,5,"!"); let _ = take(source,c,5,"{"); let _ = take(source,c,1,"read"); let _ = take(source,c,1,"r");
    let _ = take(source,c,5,","); let _ = take(source,c,1,"write"); let _ = take(source,c,1,"s"); let _ = take(source,c,5,"}");
    let requires_site = take(source,c,1,"requires"); let _ = take(source,c,5,"["); let _ = take(source,c,1,"Le"); let _ = take(source,c,5,"(");
    let _ = take(source,c,1,"n"); let _ = take(source,c,5,","); let _ = take(source,c,1,"c"); let _ = take(source,c,5,")"); let _ = take(source,c,5,"]");
    let _ = take(source,c,1,"resources"); let _ = take(source,c,5,"{"); let _ = take(source,c,1,"depth"); let _ = take(source,c,5,":"); let _ = take(source,c,2,"1");
    let _ = take(source,c,5,","); let _ = take(source,c,1,"frame"); let _ = take(source,c,5,":"); let _ = take(source,c,2,"256"); let _ = take(source,c,5,"}");
    let _ = take(source,c,5,"="); let _ = take(source,c,1,"fn"); let _ = take(source,c,5,"("); let _ = take(source,c,1,"source"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"initial"); let _ = take(source,c,5,")"); let _ = take(source,c,5,"=>"); let _ = take(source,c,1,"do"); let _ = take(source,c,5,":");
    token(source,c,6); token(source,c,7); let _ = take(source,c,1,"let"); let _ = take(source,c,1,"built"); let _ = take(source,c,5,"=");
    let for_site = take(source,c,1,"for"); let _ = take(source,c,1,"i"); let _ = take(source,c,1,"in"); let _ = take(source,c,2,"0"); let _ = take(source,c,5,"..");
    let _ = take(source,c,1,"n"); let _ = take(source,c,1,"carry"); let _ = take(source,c,5,"("); let _ = take(source,c,1,"b"); let _ = take(source,c,5,"=");
    let _ = take(source,c,1,"initial"); let _ = take(source,c,5,")"); token(source,c,6); token(source,c,7);
    let invariant_site = take(source,c,1,"invariant"); let _ = take(source,c,5,"["); let _ = take(source,c,1,"Eq"); let _ = take(source,c,5,"(");
    let _ = take(source,c,1,"Init"); let _ = take(source,c,5,"("); let _ = take(source,c,1,"b"); let _ = take(source,c,5,")"); let _ = take(source,c,5,",");
    let _ = take(source,c,1,"i"); let _ = take(source,c,5,")"); let _ = take(source,c,5,"]"); let _ = take(source,c,1,"do"); let _ = take(source,c,5,":");
    token(source,c,6); token(source,c,7); let next_site = take(source,c,1,"next"); let _ = take(source,c,5,"(");
    let _ = take(source,c,1,"builder"); let _ = take(source,c,5,"."); let append_site = take(source,c,1,"append"); let _ = take(source,c,5,"(");
    let _ = take(source,c,1,"b"); let _ = take(source,c,5,","); let read_site = take(source,c,1,"source"); let _ = take(source,c,5,"[");
    let _ = take(source,c,1,"i"); let _ = take(source,c,5,"]"); let _ = take(source,c,5,")"); let _ = take(source,c,5,")");
    if c.t.kind == 6 { next(source,c); } token(source,c,8); token(source,c,8);
    let return_site = take(source,c,1,"return"); let _ = take(source,c,1,"built"); if c.t.kind == 6 { next(source,c); } token(source,c,8);
    while !c.bad && c.t.kind == 6 { next(source,c); }
    if c.bad || c.t.kind != 0 { return loop_core::Core {},1; }
    let sites = loop_core::Sites { requires_site: requires_site, for_site: for_site, invariant_site: invariant_site,
        next_site: next_site, append_site: append_site, read_site: read_site, return_site: return_site };
    return loop_core::Core { source: source, context: context, sites: sites,
        evidence: loop_core::evidence(context,sites), ops: loop_core::ops(context,sites) },0;
}
